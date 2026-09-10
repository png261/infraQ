"use client"

import { Database, Github, KeyRound, Plus, Save, Settings, Trash2 } from "lucide-react"
import { FormEvent, useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { StateBackendManager } from "@/components/settings/StateBackendManager"
import { useAuth } from "@/hooks/useAuth"
import {
  AwsCredentialMetadata,
  deleteAwsCredential,
  listAwsCredentials,
  saveAwsCredential,
} from "@/services/resourcesService"
import { AgentCoreClient } from "@/lib/agentcore-client"
import { cn } from "@/lib/utils"
import { useWebAppStore } from "@/stores/webAppStore"

type AwsExports = {
  githubAppInstallUrl?: string | null
  agentRuntimeArn?: string | null
  awsRegion?: string | null
}

type SettingsTab = "general" | "credentials" | "state-backend"

const settingsTabs: Array<{
  id: SettingsTab
  label: string
  description: string
  icon: typeof Settings
}> = [
  {
    id: "general",
    label: "General",
    description: "GitHub App and workspace connection",
    icon: Settings,
  },
  {
    id: "credentials",
    label: "Credentials",
    description: "User-scoped AWS access keys",
    icon: KeyRound,
  },
  {
    id: "state-backend",
    label: "State Backend",
    description: "Terraform state sources",
    icon: Database,
  },
]

export default function SettingsPage() {
  const auth = useAuth()
  const [activeTab, setActiveTab] = useState<SettingsTab>("general")
  const catalog = useWebAppStore(state => state.resourceCatalog)
  const loadResourceCatalog = useWebAppStore(state => state.loadResourceCatalog)
  const setResourceCatalog = useWebAppStore(state => state.setResourceCatalog)
  const [installUrl, setInstallUrl] = useState<string | null>(null)
  const [client, setClient] = useState<AgentCoreClient | null>(null)
  const [credentials, setCredentials] = useState<AwsCredentialMetadata[]>([])
  const [activeCredentialId, setActiveCredentialId] = useState("")
  const [isGithubInstalled, setIsGithubInstalled] = useState(false)
  const [isAddCredentialOpen, setIsAddCredentialOpen] = useState(false)
  const [credentialForm, setCredentialForm] = useState({
    credentialId: "",
    accessKeyId: "",
    secretAccessKey: "",
  })
  const [isSavingCredential, setIsSavingCredential] = useState(false)
  const [deletingCredentialId, setDeletingCredentialId] = useState<string | null>(null)
  const [credentialMessage, setCredentialMessage] = useState<string | null>(null)
  const [credentialError, setCredentialError] = useState<string | null>(null)
  const backendsByCredentialId = catalog.backends.reduce<Record<string, number>>((counts, backend) => {
    if (backend.credentialId) {
      counts[backend.credentialId] = (counts[backend.credentialId] ?? 0) + 1
    }
    return counts
  }, {})

  useEffect(() => {
    let cancelled = false
    fetch("/aws-exports.json")
      .then(response => (response.ok ? response.json() : Promise.reject(response.statusText)))
      .then((loaded: AwsExports) => {
        if (cancelled) return
        setInstallUrl(loaded.githubAppInstallUrl ?? null)
        if (loaded.agentRuntimeArn) {
          setClient(new AgentCoreClient({
            runtimeArn: loaded.agentRuntimeArn,
            region: loaded.awsRegion || "ap-southeast-1",
          }))
        }
      })
      .catch(() => {
        if (!cancelled) setInstallUrl(null)
      })
    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    const idToken = auth.user?.id_token
    if (!idToken) return

    let cancelled = false
    listAwsCredentials(idToken)
      .then(loaded => {
        if (cancelled) return
        setCredentials(loaded.credentials)
        const activeId = loaded.activeCredentialId || loaded.credentials[0]?.credentialId || ""
        setActiveCredentialId(activeId)
      })
      .catch(error => {
        if (!cancelled) setCredentialError(error instanceof Error ? error.message : "Load failed")
      })
    return () => {
      cancelled = true
    }
  }, [auth.user?.id_token])

  useEffect(() => {
    const idToken = auth.user?.id_token
    if (!idToken) return
    loadResourceCatalog(idToken).catch(() => undefined)
  }, [auth.user?.id_token, loadResourceCatalog])

  useEffect(() => {
    const accessToken = auth.user?.access_token
    if (!client || !accessToken) return
    let cancelled = false
    client.githubAction("listInstalledRepositories", crypto.randomUUID(), accessToken, null)
      .then(response => {
        if (cancelled) return
        const repositories = ((response as any)?.repositories ?? []) as unknown[]
        const accounts = ((response as any)?.accounts ?? []) as unknown[]
        setIsGithubInstalled(repositories.length > 0 || accounts.length > 0)
      })
      .catch(() => {
        if (!cancelled) setIsGithubInstalled(false)
      })
    return () => {
      cancelled = true
    }
  }, [auth.user?.access_token, client])

  async function handleSaveCredential(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const idToken = auth.user?.id_token
    if (!idToken) {
      setCredentialError("Sign in before saving AWS credentials")
      return
    }

    setIsSavingCredential(true)
    setCredentialError(null)
    setCredentialMessage(null)
    try {
      const saved = await saveAwsCredential(credentialForm, idToken)
      setCredentials(current => [saved, ...current.filter(item => item.credentialId !== saved.credentialId)])
      setActiveCredentialId(saved.credentialId ?? "")
      setResourceCatalog(current => ({
        ...current,
        credentials: [saved, ...current.credentials.filter(item => item.credentialId !== saved.credentialId)],
      }), idToken)
      setCredentialForm({
        credentialId: "",
        accessKeyId: "",
        secretAccessKey: "",
      })
      setIsAddCredentialOpen(false)
      setCredentialMessage("AWS credential saved")
    } catch (error) {
      setCredentialError(error instanceof Error ? error.message : "Failed to save credential")
    } finally {
      setIsSavingCredential(false)
    }
  }

  async function handleDeleteCredential(credential: AwsCredentialMetadata) {
    const idToken = auth.user?.id_token
    const credentialId = credential.credentialId
    if (!idToken) {
      setCredentialError("Sign in before removing AWS credentials")
      return
    }
    if (!credentialId) return

    const relatedBackendCount = backendsByCredentialId[credentialId] ?? 0
    const label = credential.name || credential.accessKeyIdSuffix || "AWS credential"
    const warning = relatedBackendCount > 0
      ? `Remove "${label}"? This also removes ${relatedBackendCount} state backend${relatedBackendCount === 1 ? "" : "s"} and related scans, drift guards, and Terraform jobs.`
      : `Remove "${label}"?`
    if (!window.confirm(warning)) return

    setDeletingCredentialId(credentialId)
    setCredentialError(null)
    setCredentialMessage(null)
    try {
      const deleted = await deleteAwsCredential(credentialId, idToken)
      const deletedBackendIds = new Set(deleted.deletedBackends.map(backend => backend.backendId))
      setCredentials(current => current.filter(item => item.credentialId !== credentialId))
      setActiveCredentialId(deleted.activeCredentialId || "")
      setResourceCatalog(current => ({
        ...current,
        credentials: current.credentials.filter(item => item.credentialId !== credentialId),
        backends: current.backends.filter(backend => !deletedBackendIds.has(backend.backendId)),
        stateResources: current.stateResources.filter(resource => !deletedBackendIds.has(resource.backendId)),
        scans: current.scans.filter(scan => !deletedBackendIds.has(scan.backendId)),
        guards: current.guards.filter(guard => !deletedBackendIds.has(guard.backendId)),
      }), idToken)
      setCredentialMessage(
        deleted.deletedBackendCount > 0
          ? `AWS credential removed with ${deleted.deletedBackendCount} related state backend${deleted.deletedBackendCount === 1 ? "" : "s"}`
          : "AWS credential removed"
      )
    } catch (error) {
      setCredentialError(error instanceof Error ? error.message : "Failed to remove credential")
    } finally {
      setDeletingCredentialId(null)
    }
  }

  return (
    <main className="min-h-screen bg-slate-50">
      <header className="border-b border-slate-200 bg-white px-6 py-5">
        <div className="mx-auto flex max-w-6xl items-center justify-between">
          <div>
            <h1 className="text-xl font-semibold text-slate-950">Settings</h1>
            <p className="mt-1 text-sm text-slate-500">Manage integrations, credentials, and Terraform state access.</p>
          </div>
        </div>
      </header>
      <section className="mx-auto grid max-w-6xl gap-6 p-6 lg:grid-cols-[280px_minmax(0,1fr)]">
        <nav
          aria-label="Settings sections"
          className="h-fit rounded-lg border border-slate-200 bg-white p-2 shadow-sm shadow-slate-950/5"
          role="tablist"
        >
          {settingsTabs.map(tab => {
            const Icon = tab.icon
            const isSelected = activeTab === tab.id
            return (
              <button
                key={tab.id}
                type="button"
                role="tab"
                aria-selected={isSelected}
                aria-controls={`${tab.id}-panel`}
                id={`${tab.id}-tab`}
                onClick={() => setActiveTab(tab.id)}
                className={cn(
                  "flex w-full items-start gap-3 rounded-md px-3 py-3 text-left transition-colors",
                  isSelected
                    ? "bg-slate-950 text-white shadow-sm"
                    : "text-slate-600 hover:bg-slate-100 hover:text-slate-950"
                )}
              >
                <Icon className={cn("mt-0.5 h-4 w-4", isSelected ? "text-white" : "text-slate-500")} />
                <span className="min-w-0">
                  <span className="block text-sm font-semibold">{tab.label}</span>
                  <span className={cn("mt-0.5 block text-xs", isSelected ? "text-slate-200" : "text-slate-500")}>
                    {tab.description}
                  </span>
                </span>
              </button>
            )
          })}
        </nav>

        <div className="min-w-0">
          {activeTab === "general" && (
            <section
              aria-labelledby="general-tab"
              className="rounded-lg border border-slate-200 bg-white p-5 shadow-sm shadow-slate-950/5"
              id="general-panel"
              role="tabpanel"
            >
              <div className="flex items-start gap-3">
                <Github className="mt-0.5 h-5 w-5 text-slate-800" />
                <div>
                  <h2 className="text-base font-semibold text-slate-900">General Settings</h2>
                  <p className="text-sm text-slate-500">
                    Connect the GitHub App used to clone repositories and open pull requests.
                  </p>
                </div>
              </div>
              <div className="mt-5 rounded-lg border border-slate-200 bg-slate-50 p-4">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <h3 className="text-sm font-semibold text-slate-900">GitHub App</h3>
                    <p className="mt-1 text-sm text-slate-500">
                      {isGithubInstalled
                        ? "The GitHub App is installed for at least one repository or account."
                        : "Install the GitHub App on repositories AgentCore can work with."}
                    </p>
                  </div>
                  {isGithubInstalled ? (
                    <Button asChild variant="destructive">
                      <a href="https://github.com/settings/installations" rel="noreferrer" target="_blank">
                        Uninstall GitHub App
                      </a>
                    </Button>
                  ) : installUrl ? (
                    <Button asChild>
                      <a href={installUrl} rel="noreferrer" target="_blank">
                        Install GitHub App
                      </a>
                    </Button>
                  ) : null}
                </div>
                {!isGithubInstalled && !installUrl && (
                  <p className="mt-4 rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-700">
                    GitHub App install URL is not configured. Set backend.github.app_slug in
                    infra-cdk/config.yaml and redeploy.
                  </p>
                )}
              </div>
            </section>
          )}

          {activeTab === "credentials" && (
            <section
              aria-labelledby="credentials-tab"
              className="rounded-lg border border-slate-200 bg-white p-5 shadow-sm shadow-slate-950/5"
              id="credentials-panel"
              role="tabpanel"
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="flex items-start gap-3">
                  <KeyRound className="mt-0.5 h-5 w-5 text-slate-800" />
                  <div>
                    <h2 className="text-base font-semibold text-slate-900">AWS Credentials</h2>
                    <p className="text-sm text-slate-500">
                      Store user-scoped AWS access keys and choose one when connecting a backend state.
                    </p>
                  </div>
                </div>
                <Button type="button" className="gap-2" onClick={() => setIsAddCredentialOpen(true)}>
                  <Plus className="h-4 w-4" />
                  Add Credential
                </Button>
              </div>

              {credentialMessage && <p className="mt-4 rounded-md border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-700">{credentialMessage}</p>}
              {credentialError && <p className="mt-4 rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">{credentialError}</p>}

              <div className="mt-4 overflow-hidden rounded-lg border border-slate-200">
                {credentials.length > 0 ? (
                  <div className="divide-y divide-slate-200">
                    {credentials.map(credential => {
                      const credentialId = credential.credentialId || ""
                      const relatedBackendCount = credentialId ? backendsByCredentialId[credentialId] ?? 0 : 0
                      return (
                        <div key={credentialId || credential.accessKeyIdSuffix} className="flex flex-wrap items-center justify-between gap-3 bg-white p-4">
                          <div className="min-w-0">
                            <div className="flex flex-wrap items-center gap-2">
                              <p className="font-semibold text-slate-900">
                                {credential.name || credential.accessKeyIdSuffix || "AWS credential"}
                              </p>
                              {credentialId === activeCredentialId && (
                                <span className="rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700">
                                  Active
                                </span>
                              )}
                            </div>
                            <p className="mt-1 text-sm text-slate-500">
                              {[credential.accountId, credential.accessKeyIdSuffix, credential.region].filter(Boolean).join(" · ") || "No metadata available"}
                            </p>
                            <p className="mt-1 text-xs text-slate-500">
                              {relatedBackendCount} related state backend{relatedBackendCount === 1 ? "" : "s"}
                            </p>
                          </div>
                          <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            disabled={!credentialId || deletingCredentialId === credentialId}
                            onClick={() => void handleDeleteCredential(credential)}
                            className="gap-2 text-red-700 hover:text-red-800"
                          >
                            <Trash2 className="h-4 w-4" />
                            {deletingCredentialId === credentialId ? "Removing" : "Remove"}
                          </Button>
                        </div>
                      )
                    })}
                  </div>
                ) : (
                  <div className="bg-slate-50 p-4 text-sm text-slate-500">
                    No AWS credentials saved.
                  </div>
                )}
              </div>

              <Dialog
                open={isAddCredentialOpen}
                onOpenChange={nextOpen => {
                  if (isSavingCredential) return
                  setIsAddCredentialOpen(nextOpen)
                  if (!nextOpen) {
                    setCredentialForm({ credentialId: "", accessKeyId: "", secretAccessKey: "" })
                  }
                }}
              >
                <DialogContent>
                  <DialogHeader>
                    <DialogTitle>Add AWS Credential</DialogTitle>
                    <DialogDescription>
                      Save an AWS access key for this user. The credential can be selected when adding a state backend.
                    </DialogDescription>
                  </DialogHeader>
                  <form className="grid gap-4" onSubmit={handleSaveCredential}>
                    <label className="flex flex-col gap-1 text-sm font-medium text-slate-700">
                      Access key ID
                      <Input
                        value={credentialForm.accessKeyId}
                        onChange={event =>
                          setCredentialForm(current => ({ ...current, accessKeyId: event.target.value }))
                        }
                        placeholder="AKIA..."
                      />
                    </label>
                    <label className="flex flex-col gap-1 text-sm font-medium text-slate-700">
                      Secret access key
                      <Input
                        type="password"
                        value={credentialForm.secretAccessKey}
                        onChange={event =>
                          setCredentialForm(current => ({
                            ...current,
                            secretAccessKey: event.target.value,
                          }))
                        }
                        placeholder="Secret key"
                      />
                    </label>
                    <DialogFooter>
                      <Button
                        type="button"
                        variant="outline"
                        disabled={isSavingCredential}
                        onClick={() => setIsAddCredentialOpen(false)}
                      >
                        Cancel
                      </Button>
                      <Button
                        type="submit"
                        disabled={isSavingCredential || !credentialForm.accessKeyId || !credentialForm.secretAccessKey}
                        className="gap-2"
                      >
                        <Save className="h-4 w-4" />
                        {isSavingCredential ? "Saving" : "Save Credential"}
                      </Button>
                    </DialogFooter>
                  </form>
                </DialogContent>
              </Dialog>
            </section>
          )}

          {activeTab === "state-backend" && (
            <div aria-labelledby="state-backend-tab" id="state-backend-panel" role="tabpanel">
              <StateBackendManager />
            </div>
          )}
        </div>
      </section>
    </main>
  )
}
