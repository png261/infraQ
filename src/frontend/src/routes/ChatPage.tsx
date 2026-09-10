"use client"
import ChatInterface from "@/components/chat/ChatInterface"
import { useAuth } from "@/hooks/useAuth"
import { GlobalContextProvider } from "@/app/context/GlobalContext"

export default function ChatPage() {
  const { isAuthenticated, isLoading } = useAuth()

  if (!isAuthenticated) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-white text-sm font-medium text-slate-500">
        {isLoading ? "Loading chat..." : "Redirecting to sign in..."}
      </div>
    )
  }

  return (
    <GlobalContextProvider>
      <div className="relative h-screen">
        <ChatInterface />
      </div>
    </GlobalContextProvider>
  )
}
