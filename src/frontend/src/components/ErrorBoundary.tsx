"use client"

import { Component, type ErrorInfo, type ReactNode } from "react"

type Props = {
  children: ReactNode
}

type State = {
  error: Error | null
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null }

  static getDerivedStateFromError(error: Error): State {
    return { error }
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error("Application render failed:", error, errorInfo)
  }

  render() {
    if (this.state.error) {
      return (
        <main className="flex min-h-screen items-center justify-center bg-white px-6 text-center">
          <div className="max-w-md space-y-3">
            <h1 className="text-base font-semibold text-slate-900">Something went wrong</h1>
            <p className="text-sm text-slate-600">
              Refresh the page and try the action again. The app stayed loaded so the error can be reported.
            </p>
            <pre className="max-h-40 overflow-auto rounded-md bg-slate-100 p-3 text-left text-xs text-slate-700">
              {this.state.error.message}
            </pre>
          </div>
        </main>
      )
    }

    return this.props.children
  }
}
