"use client"

import { useAppAuth } from "@/components/auth/AuthProvider"

export function useAuth() {
  const auth = useAppAuth()

  if (!auth) {
    return {
      isAuthenticated: true,
      user: null,
      signIn: async () => {},
      signOut: async () => {},
      isLoading: false,
      error: null,
      token: null,
      refreshUser: async () => null,
    }
  }

  return auth
}
