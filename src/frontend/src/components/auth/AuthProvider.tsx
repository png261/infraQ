"use client"

import { PropsWithChildren, createContext, useCallback, useContext, useEffect, useMemo, useState } from "react"
import { Amplify } from "aws-amplify"
import { fetchAuthSession, getCurrentUser, signInWithRedirect, signOut as amplifySignOut } from "aws-amplify/auth"
import { Hub } from "aws-amplify/utils"
import {
  createCognitoAuthConfig,
  cognitoAuthConfig,
  regionFromUserPoolId,
  userPoolIdFromAuthority,
  type AwsExportsConfig,
} from "@/lib/auth"

type AuthUser = {
  access_token?: string
  id_token?: string
  profile?: Record<string, unknown>
}

type RefreshUserOptions = {
  forceRefresh?: boolean
  minAccessTokenTtlSeconds?: number
}

type AuthContextValue = {
  isAuthenticated: boolean
  user: AuthUser | null
  signIn: () => Promise<void>
  signOut: () => Promise<void>
  isLoading: boolean
  error: Error | null
  token?: string | null
  refreshUser: (options?: RefreshUserOptions) => Promise<AuthUser | null>
}

const AuthContext = createContext<AuthContextValue | null>(null)

function decodeJwtPayload(token?: string): Record<string, unknown> {
  if (!token) return {}
  try {
    const payload = token.split(".")[1]
    if (!payload) return {}
    const normalized = payload.replace(/-/g, "+").replace(/_/g, "/")
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")
    return JSON.parse(window.atob(padded)) as Record<string, unknown>
  } catch {
    return {}
  }
}

function scopeList(scope?: string): string[] {
  return scope?.split(/\s+/).filter(Boolean) ?? ["email", "openid", "profile"]
}

function tokenExpiresWithin(token: string | undefined, seconds: number): boolean {
  const exp = decodeJwtPayload(token).exp
  if (typeof exp !== "number") return true
  return exp * 1000 - Date.now() <= seconds * 1000
}

function configureAmplify(config: AwsExportsConfig) {
  const userPoolId = userPoolIdFromAuthority(config.authority)
  const region = regionFromUserPoolId(userPoolId)
  if (!userPoolId || !config.client_id) {
    throw new Error("Cognito user pool configuration is incomplete")
  }
  if (!config.cognito_domain || !config.redirect_uri || !config.post_logout_redirect_uri) {
    throw new Error("Cognito Hosted UI configuration is incomplete")
  }

  Amplify.configure({
    Auth: {
      Cognito: {
        userPoolId,
        userPoolClientId: config.client_id,
        loginWith: {
          oauth: {
            domain: config.cognito_domain,
            scopes: scopeList(config.scope),
            redirectSignIn: [config.redirect_uri],
            redirectSignOut: [config.post_logout_redirect_uri],
            responseType: config.response_type === "token" ? "token" : "code",
          },
        },
      },
    },
  })

  return { region, userPoolId }
}

async function readAuthUser(options: RefreshUserOptions = {}): Promise<AuthUser | null> {
  try {
    await getCurrentUser()
    let session = await fetchAuthSession({ forceRefresh: options.forceRefresh })
    let accessToken = session.tokens?.accessToken?.toString()
    let idToken = session.tokens?.idToken?.toString()
    const minTtl = options.minAccessTokenTtlSeconds ?? 0
    if (!options.forceRefresh && accessToken && minTtl > 0 && tokenExpiresWithin(accessToken, minTtl)) {
      session = await fetchAuthSession({ forceRefresh: true })
      accessToken = session.tokens?.accessToken?.toString()
      idToken = session.tokens?.idToken?.toString()
    }
    if (!accessToken || !idToken) return null
    return {
      access_token: accessToken,
      id_token: idToken,
      profile: decodeJwtPayload(idToken),
    }
  } catch {
    return null
  }
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message
  if (typeof error === "string") return error
  return "Authentication failed"
}

const AuthProvider = ({ children }: PropsWithChildren) => {
  const [isReady, setIsReady] = useState(false)
  const [isLoading, setIsLoading] = useState(true)
  const [user, setUser] = useState<AuthUser | null>(null)
  const [error, setError] = useState<Error | null>(null)

  const refreshUser = useCallback(async (options?: RefreshUserOptions) => {
    const currentUser = await readAuthUser(options)
    setUser(currentUser)
    return currentUser
  }, [])

  const signIn = useCallback(async () => {
    setIsLoading(true)
    setError(null)
    try {
      await signInWithRedirect()
    } catch (err) {
      const nextError = err instanceof Error ? err : new Error(errorMessage(err))
      setError(nextError)
      throw nextError
    } finally {
      setIsLoading(false)
    }
  }, [])

  useEffect(() => {
    let cancelled = false

    const removeHubListener = Hub.listen("auth", ({ payload }) => {
      if (payload.event === "signedIn" || payload.event === "signInWithRedirect") {
        void refreshUser()
      }
      if (payload.event === "signedOut") {
        setUser(null)
      }
      if (payload.event === "signInWithRedirect_failure") {
        setError(new Error(errorMessage(payload.data)))
      }
    })

    async function loadConfig() {
      try {
        const config = await createCognitoAuthConfig().catch(() => cognitoAuthConfig)
        configureAmplify(config)
        const currentUser = await readAuthUser()
        if (cancelled) return
        setUser(currentUser)
        if (!currentUser) {
          await signIn()
        }
      } catch (err) {
        if (cancelled) return
        setError(err instanceof Error ? err : new Error(errorMessage(err)))
      } finally {
        if (!cancelled) {
          setIsReady(true)
          setIsLoading(false)
        }
      }
    }

    void loadConfig()
    return () => {
      cancelled = true
      removeHubListener()
    }
  }, [refreshUser, signIn])

  const signOut = useCallback(async () => {
    setIsLoading(true)
    setError(null)
    try {
      await amplifySignOut()
      setUser(null)
    } finally {
      setIsLoading(false)
    }
  }, [])

  const value = useMemo<AuthContextValue>(
    () => ({
      isAuthenticated: Boolean(user),
      user,
      signIn,
      signOut,
      isLoading,
      error,
      token: user?.id_token ?? null,
      refreshUser,
    }),
    [error, isLoading, refreshUser, signIn, signOut, user]
  )

  if (!isReady || !user) {
    return <div className="flex min-h-screen items-center justify-center bg-white text-xl text-slate-700">Redirecting to sign in...</div>
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAppAuth() {
  return useContext(AuthContext)
}

export { AuthProvider }
