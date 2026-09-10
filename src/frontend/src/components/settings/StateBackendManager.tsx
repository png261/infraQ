"use client"

import { Database, Plus, RefreshCw, Trash2 } from "lucide-react"
import { FormEvent, useCallback, useEffect, useState } from "react"
import { InstalledRepositoryCombobox } from "@/components/github/InstalledRepositoryCombobox"
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
import { useAuth } from "@/hooks/useAuth"
import { useInstalledRepositories } from "@/hooks/useInstalledRepositories"
import type { SelectedRepository } from "@/lib/agentcore-client/types"
import {
  AwsCredentialMetadata,
  S3BucketInfo,
  StateBackend,
  StateBackendResource,
  createStateBackend,
  deleteStateBackend,
  listS3Buckets,
  listStateBackendResources,
} from "@/services/resourcesService"
import { useWebAppStore } from "@/stores/webAppStore"

type ScanService = "s3" | "ec2" | "iam"

function isScanService(value: string): value is ScanService {
  return value === "s3" || value === "ec2" || value === "iam"
}

function formatDate(value: string | undefined): string {
  if (!value) return "-"
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString()
}

function AddStateBackendDialog({
  open,
  credentials,
  repositories,
  isLoadingRepositories,
  onOpenChange,
  onCreate,
  onListBuckets,
  isSaving,
}: {
  open: boolean
  credentials: AwsCredentialMetadata[]
  repositories: SelectedRepository[]
  isLoadingRepositories: boolean
  onOpenChange: (open: boolean) => void
  onCreate: (payload: {
    name: string
    bucket: string
    key: string
    region: string
    service: ScanService
    credentialId: string
    repository: SelectedRepository
  }) => Promise<void>
  onListBuckets: (credentialId: string, region: string) => Promise<S3BucketInfo[]>
  isSaving: boolean
}) {
  const [form, setForm] = useState({
    name: "",
    bucket: "",
    key: "",
    region: "ap-southeast-1",
    service: "s3" as ScanService,
    credentialId: credentials[0]?.credentialId || "",
    repository: repositories[0]?.fullName || "",
  })
  const [buckets, setBuckets] = useState<S3BucketInfo[]>([])
  const [bucketQuery, setBucketQuery] = useState("")
  const [bucketError, setBucketError] = useState<string | null>(null)
  const [isLoadingBuckets, setIsLoadingBuckets] = useState(false)

  const filteredBuckets = buckets.filter(bucket =>
    bucket.name.toLowerCase().includes(bucketQuery.trim().toLowerCase())
  )

  useEffect(() => {
    if (form.repository || repositories.length === 0) return
    setForm(current => ({ ...current, repository: repositories[0].fullName }))
  }, [form.repository, repositories])

  useEffect(() => {
    if (form.credentialId || credentials.length === 0) return
    setForm(current => ({ ...current, credentialId: credentials[0]?.credentialId || "" }))
  }, [credentials, form.credentialId])

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const repository = repositories.find(item => item.fullName === form.repository)
    if (!repository) return
    await onCreate({ ...form, repository })
    setForm(current => ({
      ...current,
      name: "",
      bucket: "",
      key: "",
    }))
  }

  async function handleBrowseBuckets() {
    if (!form.credentialId || !form.region) return
    setIsLoadingBuckets(true)
    setBucketError(null)
    try {
      setBuckets(await onListBuckets(form.credentialId, form.region))
    } catch (error) {
      setBuckets([])
      setBucketError(error instanceof Error ? error.message : "Failed to load S3 buckets")
    } finally {
      setIsLoadingBuckets(false)
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={nextOpen => {
        if (isSaving) return
        onOpenChange(nextOpen)
      }}
    >
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-3xl">
        <DialogHeader>
          <DialogTitle>Add State Backend</DialogTitle>
          <DialogDescription>
            Connect an S3 Terraform state file for Cloudrift scans. Choose credentials and region, then browse buckets or enter a bucket name manually.
          </DialogDescription>
        </DialogHeader>
        <form className="grid gap-4" onSubmit={handleSubmit}>
          <div className="grid gap-3 md:grid-cols-2">
            <label className="flex flex-col gap-1 text-sm font-medium text-slate-700">
              AWS Credential
              <select
                className="h-9 rounded-lg border border-slate-200 bg-white px-3 text-sm outline-none focus:border-slate-400 focus:ring-[3px] focus:ring-slate-200"
                value={form.credentialId}
                onChange={event => {
                  setBuckets([])
                  setForm(current => ({ ...current, credentialId: event.target.value }))
                }}
              >
                {credentials.length === 0 ? (
                  <option value="">No saved credentials</option>
                ) : (
                  credentials.map(credential => (
                    <option key={credential.credentialId} value={credential.credentialId}>
                      {credential.name || credential.accountId || credential.accessKeyIdSuffix}
                    </option>
                  ))
                )}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm font-medium text-slate-700">
              Region
              <Input
                value={form.region}
                onChange={event => {
                  setBuckets([])
                  setForm(current => ({ ...current, region: event.target.value }))
                }}
                placeholder="ap-southeast-1"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm font-medium text-slate-700">
              Name
              <Input value={form.name} onChange={event => setForm(current => ({ ...current, name: event.target.value }))} />
            </label>
            <label className="flex flex-col gap-1 text-sm font-medium text-slate-700">
              State key
              <Input value={form.key} onChange={event => setForm(current => ({ ...current, key: event.target.value }))} placeholder="env/prod/terraform.tfstate" />
            </label>
            <label className="flex flex-col gap-1 text-sm font-medium text-slate-700">
              Service
              <select
                className="h-9 rounded-lg border border-slate-200 bg-white px-3 text-sm outline-none focus:border-slate-400 focus:ring-[3px] focus:ring-slate-200"
                value={form.service}
                onChange={event => {
                  const service = isScanService(event.target.value) ? event.target.value : "s3"
                  setForm(current => ({ ...current, service }))
                }}
              >
                <option value="s3">S3</option>
                <option value="ec2">EC2</option>
                <option value="iam">IAM</option>
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm font-medium text-slate-700">
              GitHub Repository
              <InstalledRepositoryCombobox
                repositories={repositories}
                value={form.repository}
                onValueChange={repository => setForm(current => ({ ...current, repository }))}
                isLoading={isLoadingRepositories}
                placeholder="Select installed repository"
              />
            </label>
          </div>

          <div className="rounded-lg border border-slate-200 bg-slate-50 p-3">
            <div className="flex flex-wrap items-end gap-2">
              <label className="flex min-w-[240px] flex-1 flex-col gap-1 text-sm font-medium text-slate-700">
                Bucket
                <Input
                  value={form.bucket}
                  onChange={event => setForm(current => ({ ...current, bucket: event.target.value }))}
                  placeholder="my-terraform-state-bucket"
                />
              </label>
              <Button
                type="button"
                variant="outline"
                onClick={() => void handleBrowseBuckets()}
                disabled={!form.credentialId || !form.region || isLoadingBuckets}
                className="gap-2"
              >
                <RefreshCw className={`h-4 w-4 ${isLoadingBuckets ? "animate-spin" : ""}`} />
                {isLoadingBuckets ? "Browsing" : "Browse buckets"}
              </Button>
            </div>
            {bucketError && <p className="mt-2 text-sm text-red-700">{bucketError}</p>}
            {buckets.length > 0 && (
              <div className="mt-3">
                <Input
                  value={bucketQuery}
                  onChange={event => setBucketQuery(event.target.value)}
                  placeholder="Filter buckets..."
                  className="bg-white"
                />
                <div className="mt-2 max-h-48 overflow-y-auto rounded-md border bg-white">
                  {filteredBuckets.length > 0 ? (
                    filteredBuckets.map(bucket => (
                      <button
                        key={bucket.name}
                        type="button"
                        className={`flex w-full items-center justify-between gap-3 border-b px-3 py-2 text-left text-sm last:border-b-0 hover:bg-slate-50/80 ${
                          form.bucket === bucket.name ? "bg-slate-100 font-semibold text-slate-950" : "text-slate-700"
                        }`}
                        onClick={() => setForm(current => ({ ...current, bucket: bucket.name }))}
                      >
                        <span>{bucket.name}</span>
                        {bucket.createdAt && <span className="text-xs font-normal text-slate-500">{formatDate(bucket.createdAt)}</span>}
                      </button>
                    ))
                  ) : (
                    <p className="p-3 text-sm text-slate-500">No buckets match that filter.</p>
                  )}
                </div>
              </div>
            )}
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)} disabled={isSaving}>
              Cancel
            </Button>
            <Button
              type="submit"
              className="gap-2"
              disabled={
                isSaving ||
                !form.name ||
                !form.bucket ||
                !form.key ||
                !form.region ||
                !form.credentialId ||
                !repositories.some(repository => repository.fullName === form.repository)
              }
            >
              <Plus className="h-4 w-4" />
              {isSaving ? "Adding" : "Add State Backend"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

export function StateBackendManager() {
  const auth = useAuth()
  const catalog = useWebAppStore(state => state.resourceCatalog)
  const isCatalogLoading = useWebAppStore(state => state.isResourceCatalogLoading)
  const loadResourceCatalog = useWebAppStore(state => state.loadResourceCatalog)
  const setResourceCatalog = useWebAppStore(state => state.setResourceCatalog)
  const { repositories, isLoading: isLoadingRepositories, error: repositoriesError } = useInstalledRepositories(auth.user?.access_token)
  const [isAddBackendOpen, setIsAddBackendOpen] = useState(false)
  const [isSavingBackend, setIsSavingBackend] = useState(false)
  const [deletingBackendId, setDeletingBackendId] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const { backends, credentials } = catalog

  const refresh = useCallback(async (options: { force?: boolean } = {}) => {
    const idToken = auth.user?.id_token
    if (!idToken) return
    setError(null)
    try {
      await loadResourceCatalog(idToken, options)
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Failed to load state backends")
    }
  }, [auth.user?.id_token, loadResourceCatalog])

  useEffect(() => {
    void refresh()
  }, [refresh])

  const handleCreateBackend = useCallback(
    async (payload: {
      name: string
      bucket: string
      key: string
      region: string
      service: ScanService
      credentialId: string
      repository: SelectedRepository
    }) => {
      const idToken = auth.user?.id_token
      if (!idToken) {
        setError("Sign in before adding a state backend")
        return
      }
      setIsSavingBackend(true)
      setError(null)
      setMessage(null)
      try {
        const backend = await createStateBackend(payload, idToken)
        const backendResources = await listStateBackendResources(backend.backendId, idToken).catch(
          () => [] as StateBackendResource[]
        )
        setResourceCatalog(current => ({
          ...current,
          backends: [backend, ...current.backends.filter(item => item.backendId !== backend.backendId)],
          stateResources: [
            ...backendResources,
            ...current.stateResources.filter(resource => resource.backendId !== backend.backendId),
          ],
        }), idToken)
        setIsAddBackendOpen(false)
        setMessage(backend.graphKey ? "State backend added and resource graph generated" : "State backend added")
      } catch (saveError) {
        setError(saveError instanceof Error ? saveError.message : "Failed to add state backend")
      } finally {
        setIsSavingBackend(false)
      }
    },
    [auth.user?.id_token, setResourceCatalog]
  )

  const handleListBuckets = useCallback(
    async (credentialId: string, region: string) => {
      const idToken = auth.user?.id_token
      if (!idToken) throw new Error("Sign in before browsing S3 buckets")
      return listS3Buckets({ credentialId, region }, idToken)
    },
    [auth.user?.id_token]
  )

  const handleDeleteBackend = useCallback(
    async (backend: StateBackend) => {
      const idToken = auth.user?.id_token
      if (!idToken) {
        setError("Sign in before removing a state backend")
        return
      }
      if (!window.confirm(`Remove state backend "${backend.name}"? This also removes its scans and autoscan settings.`)) {
        return
      }
      setDeletingBackendId(backend.backendId)
      setError(null)
      setMessage(null)
      try {
        await deleteStateBackend(backend.backendId, idToken)
        setResourceCatalog(current => ({
          ...current,
          backends: current.backends.filter(item => item.backendId !== backend.backendId),
          stateResources: current.stateResources.filter(resource => resource.backendId !== backend.backendId),
          scans: current.scans.filter(scan => scan.backendId !== backend.backendId),
          guards: current.guards.filter(guard => guard.backendId !== backend.backendId),
        }), idToken)
        setMessage("State backend removed")
      } catch (deleteError) {
        setError(deleteError instanceof Error ? deleteError.message : "Failed to remove state backend")
      } finally {
        setDeletingBackendId(null)
      }
    },
    [auth.user?.id_token, setResourceCatalog]
  )

  return (
    <section className="rounded-lg border border-slate-200 bg-white p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="flex items-center gap-3">
          <Database className="h-5 w-5 text-slate-800" />
          <div>
            <h2 className="text-base font-semibold text-slate-900">State Backends</h2>
            <p className="text-sm text-slate-500">Add and remove Terraform state backends used by Cloudrift scans.</p>
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button type="button" variant="outline" onClick={() => void refresh({ force: true })} disabled={isCatalogLoading} className="gap-2">
            <RefreshCw className={`h-4 w-4 ${isCatalogLoading ? "animate-spin" : ""}`} />
            Reload
          </Button>
          <Button type="button" onClick={() => setIsAddBackendOpen(true)} className="gap-2">
            <Plus className="h-4 w-4" />
            Add State Backend
          </Button>
        </div>
      </div>
      {message && <p className="mt-4 rounded-md border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-700">{message}</p>}
      {error && <p className="mt-4 rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</p>}
      {repositoriesError && <p className="mt-4 rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-700">{repositoriesError}</p>}

      <div className="mt-4 overflow-hidden rounded-lg border border-slate-200">
        <table className="w-full min-w-[720px] text-left text-sm">
          <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
            <tr>
              <th className="px-4 py-3">Name</th>
              <th className="px-4 py-3">State</th>
              <th className="px-4 py-3">Credential</th>
              <th className="px-4 py-3">Repository</th>
              <th className="px-4 py-3">Updated</th>
              <th className="px-4 py-3 text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-200">
            {backends.map(backend => (
              <tr key={backend.backendId} className="align-top">
                <td className="px-4 py-4">
                  <p className="font-semibold text-slate-900">{backend.name}</p>
                  <p className="text-xs text-slate-500">{backend.service || "s3"} · {backend.region}</p>
                </td>
                <td className="break-all px-4 py-4 text-slate-600">s3://{backend.bucket}/{backend.key}</td>
                <td className="px-4 py-4 text-slate-600">{backend.credentialName || backend.credentialId || "-"}</td>
                <td className="px-4 py-4 text-slate-600">{backend.repository?.fullName || "-"}</td>
                <td className="px-4 py-4 text-slate-600">{formatDate(backend.updatedAt)}</td>
                <td className="px-4 py-4 text-right">
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => void handleDeleteBackend(backend)}
                    disabled={deletingBackendId === backend.backendId}
                    className="gap-2 text-red-700 hover:text-red-800"
                  >
                    <Trash2 className="h-4 w-4" />
                    {deletingBackendId === backend.backendId ? "Removing" : "Remove"}
                  </Button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {backends.length === 0 && (
          <p className="border-t border-slate-200 p-4 text-sm text-slate-500">No state backends connected.</p>
        )}
      </div>

      <AddStateBackendDialog
        open={isAddBackendOpen}
        credentials={credentials}
        repositories={repositories}
        isLoadingRepositories={isLoadingRepositories}
        isSaving={isSavingBackend}
        onOpenChange={setIsAddBackendOpen}
        onCreate={handleCreateBackend}
        onListBuckets={handleListBuckets}
      />
    </section>
  )
}
