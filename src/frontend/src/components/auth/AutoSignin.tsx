"use client"

import { ReactNode, useEffect, useState, PropsWithChildren } from "react"
import { useAuth } from "@/hooks/useAuth"

function AutoSigninContent({ children }: PropsWithChildren) {
  const auth = useAuth()
  const { isAuthenticated, isLoading, signIn } = auth

  useEffect(() => {
    if (!isLoading && !isAuthenticated) {
      void signIn()
    }
  }, [isAuthenticated, isLoading, signIn])

  if (isLoading) {
    return <div className="flex items-center justify-center min-h-screen text-xl">Loading...</div>
  }

  if (!isAuthenticated) {
    return null
  }

  return <>{children}</>
}

export function AutoSignin({ children }: { children: ReactNode }) {
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

  if (!mounted) {
    return null
  }

  return <AutoSigninContent>{children}</AutoSigninContent>
}
