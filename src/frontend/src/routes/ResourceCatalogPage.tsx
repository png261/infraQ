"use client"

import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react"
import { Link, useNavigate } from "react-router-dom"
import {
  AlertTriangle,
  BarChart3,
  Boxes,
  CalendarClock,
  CheckCircle2,
  Clock3,
  Database,
  FileClock,
  GitPullRequest,
  History,
  Play,
  Network,
  RefreshCw,
  ShieldAlert,
  Wrench,
} from "lucide-react"
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
import type { SelectedRepository, SelectedStateBackend } from "@/lib/agentcore-client/types"
import { useWebAppStore } from "@/stores/webAppStore"
import type { ChatSession, PullRequestInfo } from "@/components/chat/types"
import {
  DriftGuard,
  ResourceScan,
  StateBackend,
  StateBackendResource,
  getStateBackendGraphUrl,
  runDriftGuard,
  saveDriftGuard,
} from "@/services/resourcesService"

type CatalogTab = "resources" | "visualize" | "state" | "autoscan" | "drift" | "policy" | "scans"
type JsonRecord = Record<string, unknown>
type AlertKind = "drift" | "policy"
type PullRequestAction = {
  number?: number
  url: string
}

type SelectedAlertIssue = {
  scan: ResourceScan
  item: unknown
  kind: AlertKind
}

type DriftDiffRow = {
  attribute: string
  expected: unknown
  actual: unknown
  hasConcreteValues: boolean
}

type EmbeddedGraph = {
  backendId: string
  backendName: string
  url: string
  generatedAt?: string
  resourceCount?: number
}

type ResourceRow = {
  key: string
  scan: ResourceScan
  source: "state" | "scan"
  repository: SelectedRepository | null
  stateBackend: SelectedStateBackend | null
  resource: JsonRecord
  after: JsonRecord
  displayName: string
  subtitle: string
  resourceType: string
  status: "active" | "drifted" | "has alert"
  driftAlerts: unknown[]
  policyAlerts: unknown[]
  consoleUrl: string
  lastUpdated: string
}

const tabs: Array<{ value: CatalogTab; label: string; icon: typeof Boxes }> = [
  { value: "resources", label: "Resources", icon: Boxes },
  { value: "visualize", label: "Visualize", icon: Network },
  { value: "state", label: "State History", icon: FileClock },
  { value: "autoscan", label: "Autoscan", icon: CalendarClock },
  { value: "drift", label: "Drift Alert", icon: AlertTriangle },
  { value: "policy", label: "Policy Alert", icon: ShieldAlert },
  { value: "scans", label: "Scan History", icon: History },
]

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as JsonRecord) : {}
}

function text(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : value === undefined || value === null ? fallback : String(value)
}

function formatDate(value: string | undefined): string {
  if (!value) return "-"
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString()
}

function getLatestScansByBackend(scans: ResourceScan[]): ResourceScan[] {
  const latest = new Map<string, ResourceScan>()
  scans.forEach(scan => {
    const key = scan.backendId || scan.backendName || scan.scanId
    if (!latest.has(key)) latest.set(key, scan)
  })
  return [...latest.values()]
}

function getResourceAfter(resource: JsonRecord): JsonRecord {
  return asRecord(asRecord(resource.change).after)
}

function getResourceValues(resource: JsonRecord): JsonRecord {
  const after = getResourceAfter(resource)
  if (Object.keys(after).length) return after
  return asRecord(resource.values)
}

function getResourceAddress(resource: JsonRecord, after: JsonRecord): string {
  return (
    text(resource.address) ||
    text(resource.name) ||
    text(after.name) ||
    text(after.id) ||
    text(after.bucket) ||
    text(after.arn) ||
    "Resource"
  )
}

function getResourceName(resource: JsonRecord, after: JsonRecord): string {
  return (
    text(asRecord(after.tags).Name) ||
    text(after.bucket) ||
    text(after.name) ||
    text(after.id) ||
    text(resource.name) ||
    getResourceAddress(resource, after)
  )
}

function uniqueTexts(values: unknown[]): string[] {
  const seen = new Set<string>()
  values.forEach(value => {
    const current = text(value).trim()
    if (current) seen.add(current)
  })
  return [...seen]
}

function getResourceCandidates(resource: JsonRecord, after: JsonRecord): string[] {
  return uniqueTexts([
    resource.address,
    resource.name,
    resource.type,
    after.id,
    after.name,
    after.bucket,
    after.arn,
    after.instance_id,
    asRecord(after.tags).Name,
  ]).map(value => value.toLowerCase())
}

function getAlertCandidates(alert: JsonRecord): string[] {
  return uniqueTexts([
    alert.resource_address,
    alert.resource_id,
    alert.resource_name,
    alert.resource_type,
    alert.address,
    alert.name,
  ]).map(value => value.toLowerCase())
}

function alertMatchesResource(alert: unknown, resource: JsonRecord, after: JsonRecord): boolean {
  const resourceCandidates = getResourceCandidates(resource, after)
  const alertCandidates = getAlertCandidates(asRecord(alert))
  if (!resourceCandidates.length || !alertCandidates.length) return false
  return alertCandidates.some(candidate =>
    resourceCandidates.some(resourceCandidate =>
      candidate === resourceCandidate ||
      candidate.includes(resourceCandidate) ||
      resourceCandidate.includes(candidate)
    )
  )
}

function buildAwsConsoleUrl(scan: ResourceScan, resource: JsonRecord, after: JsonRecord): string {
  const region = scan.stateRegion || "ap-southeast-1"
  const typeName = text(resource.type).toLowerCase()
  const id = text(after.id) || text(after.instance_id)
  const bucket = text(after.bucket) || text(resource.name)

  if (typeName === "aws_instance" && id.startsWith("i-")) {
    return `https://${region}.console.aws.amazon.com/ec2/home?region=${region}#InstanceDetails:instanceId=${encodeURIComponent(id)}`
  }
  if (typeName === "aws_security_group" && id.startsWith("sg-")) {
    return `https://${region}.console.aws.amazon.com/ec2/home?region=${region}#SecurityGroup:groupId=${encodeURIComponent(id)}`
  }
  if (typeName === "aws_s3_bucket" && bucket) {
    return `https://s3.console.aws.amazon.com/s3/buckets/${encodeURIComponent(bucket)}?region=${region}&bucketType=general`
  }
  if (typeName.startsWith("aws_iam_")) return "https://ap-southeast-1.console.aws.amazon.com/iam/home"
  return ""
}

function repositoryForScan(scan: ResourceScan, backends: StateBackend[]): SelectedRepository | null {
  return scan.repository ?? backends.find(backend => backend.backendId === scan.backendId)?.repository ?? null
}

function stateBackendForScan(scan: ResourceScan, backends: StateBackend[]): SelectedStateBackend | null {
  const backend = backends.find(item => item.backendId === scan.backendId)
  if (backend) return backend
  if (!scan.backendId || !scan.stateBucket || !scan.stateKey || !scan.stateRegion) return null
  return {
    backendId: scan.backendId,
    name: scan.backendName || scan.backendId,
    bucket: scan.stateBucket,
    key: scan.stateKey,
    region: scan.stateRegion,
    service: scan.service,
    repository: scan.repository ?? null,
  }
}

function stateResourceKey(resource: JsonRecord): string {
  return text(resource.address) || `${text(resource.type)}.${text(resource.name)}`
}

function scanForStateResource(resource: StateBackendResource, scan: ResourceScan | undefined): ResourceScan {
  return scan ?? {
    scanId: `state-${resource.backendId}`,
    backendId: resource.backendId,
    backendName: resource.backendName,
    stateBucket: resource.stateBucket,
    stateKey: resource.stateKey,
    stateRegion: resource.stateRegion,
    service: resource.service,
    status: "SUCCEEDED",
    startedAt: resource.updatedAt || "",
    updatedAt: resource.updatedAt || "",
    driftAlerts: [],
    policyAlerts: [],
    currentResources: [],
    repository: resource.repository,
  }
}

function buildScanRows(scans: ResourceScan[], backends: StateBackend[], skippedBackends: Set<string>): ResourceRow[] {
  return getLatestScansByBackend(scans).flatMap(scan => {
    if (skippedBackends.has(scan.backendId)) return []
    return scan.currentResources.map((item, index) => {
      const resource = asRecord(item)
      const after = getResourceValues(resource)
      const driftAlerts = scan.driftAlerts.filter(alert => alertMatchesResource(alert, resource, after))
      const policyAlerts = scan.policyAlerts.filter(alert => alertMatchesResource(alert, resource, after))
      const resourceType = text(resource.type, "unknown")
      const displayName = getResourceName(resource, after)
      const address = getResourceAddress(resource, after)
      return {
        key: `${scan.scanId}-${address}-${index}`,
        scan,
        source: "scan" as const,
        repository: repositoryForScan(scan, backends),
        stateBackend: stateBackendForScan(scan, backends),
        resource,
        after,
        displayName,
        subtitle: address === displayName ? text(after.arn) : address,
        resourceType,
        status: driftAlerts.length ? "drifted" : policyAlerts.length ? "has alert" : "active",
        driftAlerts,
        policyAlerts,
        consoleUrl: buildAwsConsoleUrl(scan, resource, after),
        lastUpdated: scan.updatedAt || scan.startedAt,
      }
    })
  })
}

function buildResourceRows(scans: ResourceScan[], backends: StateBackend[], stateResources: StateBackendResource[]): ResourceRow[] {
  const latestScans = getLatestScansByBackend(scans)
  const latestScanByBackend = new Map(latestScans.map(scan => [scan.backendId, scan]))
  const stateBackends = new Set(stateResources.map(resource => resource.backendId))
  const stateRows = stateResources.map((item, index) => {
    const resource = asRecord(item)
    const after = getResourceValues(resource)
    const backend = backends.find(current => current.backendId === item.backendId)
    const scan = scanForStateResource(item, latestScanByBackend.get(item.backendId))
    const driftAlerts = scan.driftAlerts.filter(alert => alertMatchesResource(alert, resource, after))
    const policyAlerts = scan.policyAlerts.filter(alert => alertMatchesResource(alert, resource, after))
    const resourceType = text(resource.type, "unknown")
    const displayName = getResourceName(resource, after)
    const address = getResourceAddress(resource, after)
    return {
      key: `state-${item.backendId}-${stateResourceKey(resource)}-${index}`,
      scan,
      source: "state" as const,
      repository: item.repository ?? backend?.repository ?? null,
      stateBackend: backend ?? stateBackendForScan(scan, backends),
      resource,
      after,
      displayName,
      subtitle: address === displayName ? text(after.arn) : address,
      resourceType,
      status: driftAlerts.length ? "drifted" as const : policyAlerts.length ? "has alert" as const : "active" as const,
      driftAlerts,
      policyAlerts,
      consoleUrl: buildAwsConsoleUrl(scan, resource, after),
      lastUpdated: item.updatedAt || scan.updatedAt || scan.startedAt,
    }
  })
  return [...stateRows, ...buildScanRows(scans, backends, stateBackends)]
}

function statusClass(status: string): string {
  const value = status.toLowerCase()
  if (value === "running" || value === "in_progress") return "border-sky-200 bg-sky-50 text-sky-700"
  if (value === "failed" || value === "drifted") return "border-red-200 bg-red-50 text-red-700"
  if (value === "has alert") return "border-amber-200 bg-amber-50 text-amber-700"
  return "border-emerald-200 bg-emerald-50 text-emerald-700"
}

function StatusBadge({ children }: { children: string }) {
  return (
    <span className={`inline-flex rounded-full border px-2.5 py-1 text-xs font-medium ${statusClass(children)}`}>
      {children}
    </span>
  )
}

function getAlertTitle(item: unknown, kind: AlertKind): string {
  const alert = asRecord(item)
  if (kind === "policy") return text(alert.policy_name) || text(alert.policy_id) || "Policy finding"
  return text(alert.resource_name) || text(alert.resource_id) || text(alert.resource_address) || "Drift finding"
}

function getAlertResource(item: unknown): string {
  const alert = asRecord(item)
  return text(alert.resource_address) || text(alert.resource_name) || text(alert.resource_id) || text(alert.resource_type) || "-"
}

function alertSeverity(item: unknown, kind: AlertKind): string {
  return text(asRecord(item).severity, kind === "drift" ? "warning" : "info")
}

function normalizedSearchText(value: unknown): string {
  return text(value).trim().toLowerCase()
}

function sessionSearchText(session: ChatSession): string {
  return [
    session.name,
    session.history?.map(message => [
      message.content,
      message.segments?.map(segment => segment.type === "text" ? segment.content : segment.toolCall.input).join("\n"),
    ].join("\n")).join("\n"),
  ].join("\n").toLowerCase()
}

function pullRequestAction(pullRequest: PullRequestInfo | null | undefined): PullRequestAction | null {
  if (!pullRequest?.url) return null
  return { number: pullRequest.number, url: pullRequest.url }
}

function alertTokens(item: unknown, kind: AlertKind): string[] {
  const alert = asRecord(item)
  return uniqueTexts([
    getAlertTitle(item, kind),
    getAlertResource(item),
    alert.resource_address,
    alert.resource_id,
    alert.resource_name,
    alert.resource_type,
    alert.policy_id,
    alert.policy_name,
    alert.message,
  ]).map(normalizedSearchText)
}

function alertFixTokens(item: unknown, kind: AlertKind): string[] {
  const alert = asRecord(item)
  const values =
    kind === "policy"
      ? [alert.policy_id, alert.policy_name, alert.message, getAlertTitle(item, kind)]
      : [alert.message, alert.resource_id]
  return uniqueTexts(values).map(normalizedSearchText)
}

function resourceTokens(row: ResourceRow): string[] {
  return uniqueTexts([
    row.displayName,
    row.subtitle,
    row.resourceType,
    row.resource.address,
    row.resource.name,
    row.after.id,
    row.after.name,
    row.after.bucket,
    row.after.arn,
    asRecord(row.after.tags).Name,
    ...row.driftAlerts.flatMap(item => alertTokens(item, "drift")),
    ...row.policyAlerts.flatMap(item => alertTokens(item, "policy")),
  ]).map(normalizedSearchText)
}

function findIssuePullRequest(params: {
  sessions: ChatSession[]
  repository?: SelectedRepository | null
  scan: ResourceScan
  tokens: string[]
}): PullRequestAction | null {
  if (!params.repository?.fullName) return null
  const tokens = params.tokens.filter(token => token.length >= 4)
  if (!tokens.length) return null
  const scanMarkers = uniqueTexts([
    params.scan.scanId,
    params.scan.backendId,
    params.scan.backendName,
    params.scan.stateBucket,
    params.scan.stateKey,
  ]).map(normalizedSearchText).filter(Boolean)

  for (const session of params.sessions) {
    if (session.repository?.fullName !== params.repository.fullName) continue
    const action = pullRequestAction(session.pullRequest)
    if (!action) continue
    const haystack = sessionSearchText(session)
    const hasScanContext = scanMarkers.some(marker => haystack.includes(marker))
    const hasIssueContext = tokens.some(token => haystack.includes(token))
    if (hasScanContext && hasIssueContext) return action
  }
  return null
}

function EmptyState({ label }: { label: string }) {
  return <div className="p-8 text-center text-sm text-slate-500">{label}</div>
}

function scanStateLabel(scan: ResourceScan): string {
  return `s3://${scan.stateBucket ?? ""}/${scan.stateKey ?? ""}`
}

function promptLine(label: string, value: unknown): string[] {
  const current = text(value).trim()
  return current ? [`${label}: ${current}`] : []
}

function promptValue(value: unknown): string {
  if (typeof value === "string") return value
  if (value === undefined || value === null) return ""
  if (typeof value === "number" || typeof value === "boolean") return String(value)
  try {
    return JSON.stringify(value)
  } catch {
    return String(value)
  }
}

function promptNestedLine(label: string, value: unknown): string[] {
  const current = promptValue(value).trim()
  return current ? [`    ${label}: ${current}`] : []
}

function promptRecordLines(label: string, value: unknown): string[] {
  const record = asRecord(value)
  const entries = Object.entries(record)
  if (!entries.length) return []
  return [
    `  ${label}:`,
    ...entries.flatMap(([key, current]) => promptNestedLine(key, current)),
  ]
}

function displayValue(value: unknown): string {
  const current = promptValue(value)
  return current || "-"
}

function recordEntries(value: unknown): Array<[string, unknown]> {
  return Object.entries(asRecord(value)).filter(([, current]) => current !== undefined && current !== null && current !== "")
}

function isCloudriftPlaceholder(value: unknown): boolean {
  const current = text(value).trim().toLowerCase()
  return current === "<planned>" || current === "<actual>" || current === "planned" || current === "actual"
}

function concreteCloudriftValue(value: unknown): unknown {
  return isCloudriftPlaceholder(value) ? undefined : value
}

function driftDiffRows(value: unknown): DriftDiffRow[] {
  return recordEntries(value).map(([attribute, current]) => {
    const values = Array.isArray(current) ? current : []
    const record = asRecord(current)
    const expected = concreteCloudriftValue(values[0] ?? record.expected ?? record.before ?? record.planned ?? record.state ?? record.desired)
    const actual = concreteCloudriftValue(values[1] ?? record.actual ?? record.after ?? record.current ?? record.live)
    return {
      attribute,
      expected,
      actual,
      hasConcreteValues: expected !== undefined || actual !== undefined,
    }
  })
}

function resourceFixContext(resource: JsonRecord | undefined, after: JsonRecord | undefined): string[] {
  if (!resource && !after) return ["Resource: not provided"]
  const currentResource = resource ?? {}
  const currentState = after ?? getResourceValues(currentResource)
  return [
    ...promptLine("Resource address", getResourceAddress(currentResource, currentState)),
    ...promptLine("Resource type", currentResource.type),
    ...promptLine("Resource name", currentResource.name),
    ...promptLine("Current ID", currentState.id || currentState.instance_id),
    ...promptLine("Current name", currentState.name),
    ...promptLine("Current bucket", currentState.bucket),
    ...promptLine("Current ARN", currentState.arn),
    ...promptLine("Current tag Name", asRecord(currentState.tags).Name),
  ]
}

function DetailField({ label, value }: { label: string; value: unknown }) {
  return (
    <div className="min-w-0">
      <dt className="text-xs font-medium uppercase tracking-wide text-slate-500">{label}</dt>
      <dd className="mt-1 break-all font-mono text-sm text-slate-900">{displayValue(value)}</dd>
    </div>
  )
}

function DetailSection({
  title,
  children,
}: {
  title: string
  children: ReactNode
}) {
  return (
    <section className="rounded-lg border border-slate-200 bg-white p-4">
      <h3 className="text-sm font-semibold text-slate-950">{title}</h3>
      <div className="mt-3">{children}</div>
    </section>
  )
}

function AttributeGrid({ values }: { values: JsonRecord }) {
  const entries = recordEntries(values)
  if (!entries.length) return <p className="text-sm text-slate-500">No attributes available.</p>
  return (
    <dl className="grid gap-3 sm:grid-cols-2">
      {entries.map(([key, value]) => (
        <DetailField key={key} label={key} value={value} />
      ))}
    </dl>
  )
}

function driftDiffLines(value: unknown): string[] {
  const rows = driftDiffRows(value)
  if (!rows.length) return []
  return [
    "  Attribute diffs:",
    "    Attribute | Expected (Terraform) | Actual (AWS)",
    ...rows.flatMap(row => {
      if (!row.hasConcreteValues) {
        return [
          `    ${row.attribute}: Cloudrift reported this attribute changed but did not return concrete expected or actual values.`,
        ]
      }
      return [
        `    ${row.attribute}:`,
        ...promptNestedLine("Expected (Terraform)", row.expected),
        ...promptNestedLine("Actual (AWS)", row.actual),
      ]
    }),
  ]
}

function AlertDetails({
  item,
  kind,
}: {
  item: unknown
  kind: AlertKind
}) {
  const alert = asRecord(item)
  const diffs = driftDiffRows(alert.diffs)
  const extraAttributes = recordEntries(alert.extra_attributes)
  const actualAttributes = recordEntries(alert.actual_attributes ?? alert.current_attributes ?? alert.live_attributes)
  const terraformAttributes = recordEntries(alert.expected_attributes ?? alert.planned_attributes ?? alert.state_attributes)

  return (
    <div className="rounded-md border border-slate-200 p-3">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="break-all text-sm font-semibold text-slate-950">{getAlertTitle(item, kind)}</p>
          <p className="mt-1 break-all text-xs text-slate-500">{getAlertResource(item)}</p>
        </div>
        <StatusBadge>{alertSeverity(item, kind)}</StatusBadge>
      </div>
      {alert.message ? <p className="mt-3 text-sm text-slate-700">{text(alert.message)}</p> : null}
      <dl className="mt-3 grid gap-3 sm:grid-cols-2">
        <DetailField label="Kind" value={kind} />
        <DetailField label="Resource type" value={alert.resource_type} />
        <DetailField label="Resource ID" value={alert.resource_id} />
        <DetailField label="Missing current" value={alert.missing} />
        {kind === "policy" ? (
          <>
            <DetailField label="Policy ID" value={alert.policy_id} />
            <DetailField label="Policy name" value={alert.policy_name} />
            <DetailField label="Remediation" value={alert.remediation} />
          </>
        ) : null}
      </dl>
      {diffs.length ? (
        <div className="mt-4">
          <p className="text-xs font-medium uppercase tracking-wide text-slate-500">Drift Visualization</p>
          <div className="mt-2 overflow-x-auto rounded-md border border-slate-200">
            <table className="w-full min-w-[640px] text-left text-sm">
              <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
                <tr>
                  <th className="px-3 py-2">Attribute</th>
                  <th className="px-3 py-2">Expected (Terraform)</th>
                  <th className="px-3 py-2">Actual (AWS)</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-200">
                {diffs.map(row => (
                  <tr key={row.attribute}>
                    <td className="break-all px-3 py-3 font-mono font-semibold text-slate-900">{row.attribute}</td>
                    <td className="break-all px-3 py-3 font-mono text-slate-700">
                      {row.hasConcreteValues ? displayValue(row.expected) : "Not returned by Cloudrift"}
                    </td>
                    <td className="break-all px-3 py-3 font-mono text-slate-700">
                      {row.hasConcreteValues ? displayValue(row.actual) : "Not returned by Cloudrift"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {diffs.some(row => !row.hasConcreteValues) ? (
            <p className="mt-2 text-sm text-slate-600">
              Cloudrift reported these attributes changed but did not return concrete expected or actual values.
            </p>
          ) : null}
        </div>
      ) : null}
      {extraAttributes.length ? (
        <div className="mt-4">
          <p className="text-xs font-medium uppercase tracking-wide text-slate-500">Extra actual/current attributes</p>
          <div className="mt-2">
            <AttributeGrid values={asRecord(alert.extra_attributes)} />
          </div>
        </div>
      ) : null}
      {terraformAttributes.length ? (
        <div className="mt-4">
          <p className="text-xs font-medium uppercase tracking-wide text-slate-500">Terraform/state attributes</p>
          <div className="mt-2">
            <AttributeGrid values={asRecord(alert.expected_attributes ?? alert.planned_attributes ?? alert.state_attributes)} />
          </div>
        </div>
      ) : null}
      {actualAttributes.length ? (
        <div className="mt-4">
          <p className="text-xs font-medium uppercase tracking-wide text-slate-500">Actual/current attributes</p>
          <div className="mt-2">
            <AttributeGrid values={asRecord(alert.actual_attributes ?? alert.current_attributes ?? alert.live_attributes)} />
          </div>
        </div>
      ) : null}
    </div>
  )
}

function driftFixContext(alert: JsonRecord): string[] {
  const lines = [
    ...promptLine("  Resource type", alert.resource_type),
    ...promptLine("  Resource ID", alert.resource_id),
    ...promptLine("  Missing from actual/current", alert.missing),
    ...driftDiffLines(alert.diffs),
    ...promptRecordLines("Extra actual/current attributes", alert.extra_attributes),
    ...promptRecordLines("Missing actual/current attributes", alert.missing_attributes),
    ...promptRecordLines("Terraform/state attributes", alert.expected_attributes ?? alert.planned_attributes ?? alert.state_attributes),
    ...promptRecordLines("Actual/current attributes", alert.actual_attributes ?? alert.current_attributes ?? alert.live_attributes),
  ]
  if (!lines.length) return []
  return [
    "  Drift detail:",
    ...lines,
    "  Change needed: compare Expected (Terraform) against Actual (AWS), update Terraform for the intended AWS values, or explicitly explain if the safer fix is to revert the live cloud change instead.",
  ]
}

function alertKindForPrompt(item: unknown, fallback: AlertKind): AlertKind {
  const alert = asRecord(item)
  return alert.policy_id || alert.policy_name ? "policy" : fallback
}

function alertFixContext(alerts: unknown[], fallbackKind: AlertKind): string[] {
  if (!alerts.length) return ["Alerts: none provided"]
  return alerts.flatMap((item, index) => {
    const alert = asRecord(item)
    const kind = alertKindForPrompt(item, fallbackKind)
    return [
      `Alert ${index + 1}:`,
      ...promptLine("  Kind", kind),
      ...promptLine("  Title", getAlertTitle(item, kind)),
      ...promptLine("  Resource", getAlertResource(item)),
      ...promptLine("  Severity", alertSeverity(item, kind)),
      ...promptLine("  Message", alert.message),
      ...promptLine("  Policy ID", alert.policy_id),
      ...promptLine("  Policy name", alert.policy_name),
      ...promptLine("  Expected", alert.expected),
      ...promptLine("  Actual", alert.actual),
      ...(kind === "drift" ? driftFixContext(alert) : []),
    ]
  })
}

function rowFixKind(row: ResourceRow): "drift" | "policy" {
  return row.driftAlerts.length > 0 ? "drift" : "policy"
}

function rowFixAlerts(row: ResourceRow): unknown[] {
  return rowFixKind(row) === "drift" ? row.driftAlerts : row.policyAlerts
}

function rowFixLabel(row: ResourceRow): string {
  return rowFixKind(row) === "drift" ? "Fix drift" : "Fix policy"
}

function buildFixPrompt(params: {
  kind: "resource" | "drift" | "policy"
  scan: ResourceScan
  repository: SelectedRepository
  resource?: JsonRecord
  after?: JsonRecord
  alerts: unknown[]
}) {
  const issueLabel =
    params.kind === "policy"
      ? "policy compliance"
      : params.kind === "drift"
        ? "Terraform drift"
        : "resource issue"
  const fallbackAlertKind: AlertKind = params.kind === "policy" ? "policy" : "drift"
  return [
    `Fix the ${issueLabel} issue found by Cloudrift in this Terraform repository.`,
    "",
    `Repository: ${params.repository.fullName}`,
    `State backend: ${scanStateLabel(params.scan)}`,
    `Backend: ${params.scan.backendName || params.scan.backendId}`,
    `Scan ID: ${params.scan.scanId}`,
    `State bucket: ${params.scan.stateBucket || "-"}`,
    `State key: ${params.scan.stateKey || "-"}`,
    `State region: ${params.scan.stateRegion || "-"}`,
    "",
    "Use the Git repository and Terraform state backend context to make the minimum Terraform changes needed, then call the create_pull_request tool with a concise generated title and a markdown body summarizing what changed.",
    "",
    "Fix only this issue context:",
    `Issue type: ${params.kind}`,
    ...resourceFixContext(params.resource, params.after),
    ...alertFixContext(params.alerts, fallbackAlertKind),
    ...promptLine("Scan status", params.scan.status),
    ...promptLine("Scan error", params.scan.error),
  ].join("\n")
}

function MetricCard({
  label,
  value,
  icon,
}: {
  label: string
  value: number | string
  icon: ReactNode
}) {
  return (
    <div className="rounded-lg border border-slate-200 bg-white p-4">
      <div className="flex items-center justify-between">
        <span className="text-sm font-medium text-slate-500">{label}</span>
        <span className="rounded-md bg-slate-100 p-2 text-slate-700">{icon}</span>
      </div>
      <p className="mt-3 text-2xl font-semibold text-slate-950">{value}</p>
    </div>
  )
}

function CloudriftAnalyticsChart({
  rows,
  scans,
  backends,
}: {
  rows: ResourceRow[]
  scans: ResourceScan[]
  backends: StateBackend[]
}) {
  const statusItems = [
    { label: "Active", value: rows.filter(row => row.status === "active").length, className: "bg-emerald-500" },
    { label: "Drifted", value: rows.filter(row => row.status === "drifted").length, className: "bg-red-500" },
    { label: "Policy", value: rows.filter(row => row.status === "has alert").length, className: "bg-amber-500" },
  ]
  const typeCounts = rows.reduce<Record<string, number>>((acc, row) => {
    const key = row.resourceType || "unknown"
    acc[key] = (acc[key] ?? 0) + 1
    return acc
  }, {})
  const topTypes = Object.entries(typeCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
  const scanHealth = [
    { label: "Succeeded", value: scans.filter(scan => scan.status === "SUCCEEDED").length, className: "bg-emerald-500" },
    { label: "Running", value: scans.filter(scan => ["RUNNING", "IN_PROGRESS"].includes(scan.status)).length, className: "bg-sky-500" },
    { label: "Failed", value: scans.filter(scan => scan.status === "FAILED").length, className: "bg-red-500" },
  ]
  const maxStatus = Math.max(1, ...statusItems.map(item => item.value))
  const maxTypes = Math.max(1, ...topTypes.map(([, value]) => value))
  const maxScanHealth = Math.max(1, ...scanHealth.map(item => item.value))

  return (
    <section className="grid gap-3 rounded-lg border border-slate-200 bg-white p-4 lg:grid-cols-[1.1fr_1fr_1fr]">
      <div>
        <div className="mb-3 flex items-center gap-2 text-sm font-semibold text-slate-900">
          <BarChart3 className="h-4 w-4" />
          Cloudrift Analysis
        </div>
        <div className="space-y-2">
          {statusItems.map(item => (
            <div key={item.label} className="grid grid-cols-[72px_1fr_36px] items-center gap-2 text-xs">
              <span className="text-slate-600">{item.label}</span>
              <div className="h-2 rounded bg-slate-100">
                <div className={`h-2 rounded ${item.className}`} style={{ width: `${(item.value / maxStatus) * 100}%` }} />
              </div>
              <span className="text-right font-medium text-slate-900">{item.value}</span>
            </div>
          ))}
        </div>
      </div>
      <div>
        <div className="mb-3 text-sm font-semibold text-slate-900">Top Resource Types</div>
        <div className="space-y-2">
          {(topTypes.length ? topTypes : [["none", 0] as [string, number]]).map(([label, value]) => (
            <div key={label} className="grid grid-cols-[minmax(82px,1fr)_1fr_30px] items-center gap-2 text-xs">
              <span className="truncate text-slate-600" title={label}>{label}</span>
              <div className="h-2 rounded bg-slate-100">
                <div className="h-2 rounded bg-slate-700" style={{ width: `${(value / maxTypes) * 100}%` }} />
              </div>
              <span className="text-right font-medium text-slate-900">{value}</span>
            </div>
          ))}
        </div>
      </div>
      <div>
        <div className="mb-3 text-sm font-semibold text-slate-900">Scan Health</div>
        <div className="space-y-2">
          {scanHealth.map(item => (
            <div key={item.label} className="grid grid-cols-[72px_1fr_36px] items-center gap-2 text-xs">
              <span className="text-slate-600">{item.label}</span>
              <div className="h-2 rounded bg-slate-100">
                <div className={`h-2 rounded ${item.className}`} style={{ width: `${(item.value / maxScanHealth) * 100}%` }} />
              </div>
              <span className="text-right font-medium text-slate-900">{item.value}</span>
            </div>
          ))}
        </div>
        <p className="mt-3 text-xs text-slate-500">{backends.length} state backends connected</p>
      </div>
    </section>
  )
}

function ResourcesTable({
  rows,
  onFixResource,
  onOpenResource,
  getPullRequest,
}: {
  rows: ResourceRow[]
  onFixResource: (row: ResourceRow) => void
  onOpenResource: (row: ResourceRow) => void
  getPullRequest: (row: ResourceRow) => PullRequestAction | null
}) {
  const [query, setQuery] = useState("")
  const filteredRows = rows.filter(row => {
    const haystack = [
      row.displayName,
      row.subtitle,
      row.resourceType,
      row.scan.backendName,
      row.scan.stateBucket,
      row.scan.stateKey,
      row.scan.service,
    ].map(value => text(value).toLowerCase()).join(" ")
    return haystack.includes(query.trim().toLowerCase())
  })

  if (!rows.length) return <EmptyState label="No connected resources found. Run a Cloudrift scan first." />

  return (
    <section className="rounded-lg border border-slate-200 bg-white">
      <div className="border-b p-4">
        <Input value={query} onChange={event => setQuery(event.target.value)} placeholder="Search resources..." className="max-w-md" />
      </div>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[1080px] text-left text-sm">
          <thead className="border-b border-slate-200 bg-white text-xs uppercase text-slate-500">
            <tr>
              <th className="px-4 py-3">Status</th>
              <th className="px-4 py-3">Resource</th>
              <th className="px-4 py-3">State Backend</th>
              <th className="px-4 py-3">Provider</th>
              <th className="px-4 py-3">Console Link</th>
              <th className="px-4 py-3">Last Updated</th>
              <th className="px-4 py-3 text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y">
            {filteredRows.map(row => {
              const pullRequest = getPullRequest(row)
              const hasIssue = row.driftAlerts.length > 0 || row.policyAlerts.length > 0
              return (
                <tr
                  key={row.key}
                  className="align-top hover:bg-slate-50/80 focus-within:bg-slate-50/80"
                >
                  <td className="px-4 py-4"><StatusBadge>{row.status}</StatusBadge></td>
                  <td className="px-4 py-4">
                    <button
                      type="button"
                      onClick={event => {
                        event.stopPropagation()
                        onOpenResource(row)
                      }}
                      className="block max-w-sm text-left"
                    >
                      <span className="block font-mono text-sm font-semibold text-slate-900 underline-offset-4 hover:underline">
                        {row.displayName}
                      </span>
                      <span className="mt-1 block break-all text-xs text-slate-500">{row.subtitle || row.resourceType}</span>
                    </button>
                  </td>
                  <td className="px-4 py-4">
                    <span className="inline-flex max-w-xs rounded-full border border-slate-200 bg-white px-2.5 py-1 text-xs font-medium text-slate-700">
                      {row.scan.backendName || row.scan.backendId}
                    </span>
                    <p className="mt-1 break-all text-xs text-slate-500">s3://{row.scan.stateBucket}/{row.scan.stateKey}</p>
                  </td>
                  <td className="px-4 py-4">
                    <p className="font-medium text-slate-800">AWS</p>
                    <p className="text-xs uppercase text-slate-500">{row.scan.service || row.resourceType}</p>
                  </td>
                  <td className="px-4 py-4">
                    {row.consoleUrl ? (
                      <a
                        href={row.consoleUrl}
                        target="_blank"
                        rel="noreferrer"
                        onClick={event => event.stopPropagation()}
                        className="font-medium text-slate-900 underline underline-offset-4"
                      >
                        Open console
                      </a>
                    ) : (
                      <span className="text-slate-500">Unavailable</span>
                    )}
                  </td>
                  <td className="px-4 py-4 text-slate-600">{formatDate(row.lastUpdated)}</td>
                  <td className="px-4 py-4 text-right" onClick={event => event.stopPropagation()}>
                    {pullRequest ? (
                      <Button asChild type="button" size="sm" variant="outline" className="gap-2">
                        <a href={pullRequest.url} target="_blank" rel="noreferrer">
                          <GitPullRequest className="h-4 w-4" />
                          View pull request
                        </a>
                      </Button>
                    ) : hasIssue && row.repository ? (
                      <Button
                        type="button"
                        size="sm"
                        variant="outline"
                        onClick={event => {
                          event.stopPropagation()
                          onFixResource(row)
                        }}
                        className="gap-2"
                      >
                        <Wrench className="h-4 w-4" />
                        {rowFixLabel(row)}
                      </Button>
                    ) : null}
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
      {filteredRows.length === 0 && <EmptyState label="No resources match that search." />}
    </section>
  )
}

function ResourceDetailsDialog({
  row,
  pullRequest,
  onOpenChange,
  onFixResource,
}: {
  row: ResourceRow | null
  pullRequest: PullRequestAction | null
  onOpenChange: (open: boolean) => void
  onFixResource: (row: ResourceRow) => void
}) {
  if (!row) return null
  const hasIssue = row.driftAlerts.length > 0 || row.policyAlerts.length > 0
  return (
    <Dialog open={Boolean(row)} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-5xl">
        <DialogHeader>
          <DialogTitle>{row.displayName}</DialogTitle>
          <DialogDescription>
            {row.resourceType} in {row.scan.backendName || row.scan.backendId}
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <DetailSection title="Resource Identity">
            <dl className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              <DetailField label="Address" value={getResourceAddress(row.resource, row.after)} />
              <DetailField label="Type" value={row.resourceType} />
              <DetailField label="Name" value={row.resource.name || row.displayName} />
              <DetailField label="Status" value={row.status} />
              <DetailField label="Provider" value={row.scan.service || "aws"} />
              <DetailField label="Last updated" value={formatDate(row.lastUpdated)} />
            </dl>
          </DetailSection>

          <DetailSection title="State Backend">
            <dl className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              <DetailField label="Backend" value={row.scan.backendName || row.scan.backendId} />
              <DetailField label="Bucket" value={row.scan.stateBucket} />
              <DetailField label="Key" value={row.scan.stateKey} />
              <DetailField label="Region" value={row.scan.stateRegion} />
              <DetailField label="Scan ID" value={row.scan.scanId} />
              <DetailField label="Scan status" value={row.scan.status} />
            </dl>
          </DetailSection>

          <DetailSection title="Current State">
            <AttributeGrid values={row.after} />
          </DetailSection>

          <DetailSection title={`Drift Findings (${row.driftAlerts.length})`}>
            {row.driftAlerts.length ? (
              <div className="space-y-3">
                {row.driftAlerts.map((item, index) => (
                  <AlertDetails key={index} item={item} kind="drift" />
                ))}
              </div>
            ) : (
              <p className="text-sm text-slate-500">No drift findings for this resource.</p>
            )}
          </DetailSection>

          <DetailSection title={`Policy Findings (${row.policyAlerts.length})`}>
            {row.policyAlerts.length ? (
              <div className="space-y-3">
                {row.policyAlerts.map((item, index) => (
                  <AlertDetails key={index} item={item} kind="policy" />
                ))}
              </div>
            ) : (
              <p className="text-sm text-slate-500">No policy findings for this resource.</p>
            )}
          </DetailSection>
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
            Close
          </Button>
          {row.consoleUrl ? (
            <Button asChild type="button" variant="outline">
              <a href={row.consoleUrl} target="_blank" rel="noreferrer">Open console</a>
            </Button>
          ) : null}
          {pullRequest ? (
            <Button asChild type="button" variant="outline" className="gap-2">
              <a href={pullRequest.url} target="_blank" rel="noreferrer">
                <GitPullRequest className="h-4 w-4" />
                View pull request
              </a>
            </Button>
          ) : hasIssue && row.repository ? (
            <Button
              type="button"
              onClick={event => {
                event.stopPropagation()
                onFixResource(row)
              }}
              className="gap-2"
            >
              <Wrench className="h-4 w-4" />
              {rowFixLabel(row)}
            </Button>
          ) : null}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function AlertIssueDetailsDialog({
  issue,
  pullRequest,
  canFix,
  onOpenChange,
  onFixAlert,
}: {
  issue: SelectedAlertIssue | null
  pullRequest: PullRequestAction | null
  canFix: boolean
  onOpenChange: (open: boolean) => void
  onFixAlert: (scan: ResourceScan, item: unknown, kind: AlertKind) => void
}) {
  if (!issue) return null
  const alert = asRecord(issue.item)
  const title = getAlertTitle(issue.item, issue.kind)
  const label = issue.kind === "drift" ? "Drift issue" : "Policy issue"
  return (
    <Dialog open={Boolean(issue)} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-4xl">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>
            {label} for {getAlertResource(issue.item)}
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <DetailSection title="Issue Context">
            <dl className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              <DetailField label="Issue type" value={issue.kind} />
              <DetailField label="Resource" value={getAlertResource(issue.item)} />
              <DetailField label="Severity" value={alertSeverity(issue.item, issue.kind)} />
              <DetailField label="Resource type" value={alert.resource_type} />
              <DetailField label="Resource ID" value={alert.resource_id} />
              <DetailField label="Message" value={alert.message} />
            </dl>
          </DetailSection>

          <DetailSection title="State Backend">
            <dl className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              <DetailField label="Backend" value={issue.scan.backendName || issue.scan.backendId} />
              <DetailField label="Bucket" value={issue.scan.stateBucket} />
              <DetailField label="Key" value={issue.scan.stateKey} />
              <DetailField label="Region" value={issue.scan.stateRegion} />
              <DetailField label="Scan ID" value={issue.scan.scanId} />
              <DetailField label="Scan status" value={issue.scan.status} />
              <DetailField label="Last detected" value={formatDate(issue.scan.updatedAt || issue.scan.startedAt)} />
              <DetailField label="First detected" value={formatDate(issue.scan.startedAt)} />
            </dl>
          </DetailSection>

          <DetailSection title={issue.kind === "drift" ? "Drift Detail" : "Policy Detail"}>
            <AlertDetails item={issue.item} kind={issue.kind} />
          </DetailSection>
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
            Close
          </Button>
          {pullRequest ? (
            <Button asChild type="button" variant="outline" className="gap-2">
              <a href={pullRequest.url} target="_blank" rel="noreferrer">
                <GitPullRequest className="h-4 w-4" />
                View pull request
              </a>
            </Button>
          ) : canFix ? (
            <Button
              type="button"
              onClick={event => {
                event.stopPropagation()
                onFixAlert(issue.scan, issue.item, issue.kind)
              }}
              className="gap-2"
            >
              <Wrench className="h-4 w-4" />
              Fix error
            </Button>
          ) : null}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function StateHistoryTable({ backends, scans }: { backends: StateBackend[]; scans: ResourceScan[] }) {
  const rows = scans.map(scan => {
    const backend = backends.find(item => item.backendId === scan.backendId)
    return { scan, backend }
  })

  if (!rows.length) return <EmptyState label="No backend state history found. Run a scan to create state history." />

  return (
    <section className="rounded-lg border border-slate-200 bg-white">
      <div className="overflow-x-auto">
        <table className="w-full min-w-[980px] text-left text-sm">
          <thead className="border-b border-slate-200 bg-white text-xs uppercase text-slate-500">
            <tr>
              <th className="px-4 py-3">State Backend</th>
              <th className="px-4 py-3">State Location</th>
              <th className="px-4 py-3">Resources</th>
              <th className="px-4 py-3">Drift</th>
              <th className="px-4 py-3">Policy</th>
              <th className="px-4 py-3">Captured</th>
            </tr>
          </thead>
          <tbody className="divide-y">
            {rows.map(({ scan, backend }) => (
              <tr key={scan.scanId} className="align-top hover:bg-slate-50/80">
                <td className="px-4 py-4">
                  <p className="font-semibold text-slate-900">{backend?.name || scan.backendName || scan.backendId}</p>
                  <p className="text-xs text-slate-500">{scan.service || backend?.service || "s3"}</p>
                </td>
                <td className="px-4 py-4 break-all text-slate-600">s3://{scan.stateBucket || backend?.bucket}/{scan.stateKey || backend?.key}</td>
                <td className="px-4 py-4 text-slate-600">{scan.currentResources.length}</td>
                <td className="px-4 py-4 text-slate-600">{scan.driftAlerts.length}</td>
                <td className="px-4 py-4 text-slate-600">{scan.policyAlerts.length}</td>
                <td className="px-4 py-4 text-slate-600">{formatDate(scan.startedAt)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  )
}

function ResourceGraphViewer({
  backends,
  openingBackendId,
  embeddedGraph,
  onLoadGraph,
}: {
  backends: StateBackend[]
  openingBackendId: string | null
  embeddedGraph: EmbeddedGraph | null
  onLoadGraph: (backend: StateBackend) => void
}) {
  if (!backends.length) {
    return <EmptyState label="No imported S3 state backends found. Add a state backend first." />
  }

  return (
    <section className="rounded-lg border border-slate-200 bg-white">
      <div className="border-b p-4">
        <h2 className="text-sm font-semibold text-slate-950">Resource Graph Viewer</h2>
        <p className="mt-1 text-sm text-slate-500">
          AWS icon diagrams are generated from the imported S3 Terraform state file when the backend is added.
        </p>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[1080px] text-left text-sm">
          <thead className="border-b border-slate-200 bg-white text-xs uppercase text-slate-500">
            <tr>
              <th className="px-4 py-3">State Backend</th>
              <th className="px-4 py-3">S3 State File</th>
              <th className="px-4 py-3">Last Graph</th>
              <th className="px-4 py-3">Resources</th>
              <th className="px-4 py-3">Status</th>
              <th className="px-4 py-3 text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y">
            {backends.map(backend => {
              const canOpen = Boolean(backend.graphKey)
              const isOpening = openingBackendId === backend.backendId
              return (
                <tr
                  key={backend.backendId}
                  className={`align-top hover:bg-slate-50/80 ${
                    embeddedGraph?.backendId === backend.backendId ? "bg-slate-50/80" : ""
                  }`}
                >
                  <td className="px-4 py-4">
                    <p className="font-semibold text-slate-900">{backend.name}</p>
                    <p className="text-xs text-slate-500">{backend.service || "s3"}</p>
                  </td>
                  <td className="px-4 py-4 break-all text-slate-600">s3://{backend.bucket}/{backend.key}</td>
                  <td className="px-4 py-4 text-slate-600">
                    {backend.graphGeneratedAt ? formatDate(backend.graphGeneratedAt) : "-"}
                    {backend.graphError && <p className="mt-1 max-w-sm text-xs text-red-700">{backend.graphError}</p>}
                  </td>
                  <td className="px-4 py-4 text-slate-600">{backend.graphResourceCount ?? "-"}</td>
                  <td className="px-4 py-4">
                    <StatusBadge>{backend.graphKey ? "ready" : backend.graphError ? "failed" : "pending"}</StatusBadge>
                  </td>
                  <td className="px-4 py-4 text-right">
                    <div className="flex justify-end gap-2">
                      <Button
                        type="button"
                        size="sm"
                        onClick={() => onLoadGraph(backend)}
                        disabled={!canOpen || isOpening}
                        className="gap-2"
                      >
                        {isOpening ? <RefreshCw className="h-4 w-4 animate-spin" /> : <Network className="h-4 w-4" />}
                        {isOpening ? "Loading" : embeddedGraph?.backendId === backend.backendId ? "Refresh graph" : "View graph"}
                      </Button>
                    </div>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
      <div className="border-t border-slate-200 bg-white p-4">
        {embeddedGraph ? (
          <div>
            <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
              <div>
                <p className="text-sm font-semibold text-slate-950">{embeddedGraph.backendName}</p>
                <p className="text-xs text-slate-500">
                  {embeddedGraph.generatedAt ? `Generated ${formatDate(embeddedGraph.generatedAt)}` : "Generated graph"}
                  {typeof embeddedGraph.resourceCount === "number" ? ` · ${embeddedGraph.resourceCount} resources` : ""}
                </p>
              </div>
            </div>
            <iframe
              title={`Resource graph for ${embeddedGraph.backendName}`}
              src={embeddedGraph.url}
              className="h-[720px] w-full rounded-md border bg-white"
              sandbox="allow-scripts allow-same-origin allow-downloads"
              referrerPolicy="no-referrer"
            />
          </div>
        ) : (
          <div className="flex h-64 items-center justify-center rounded-md border border-dashed bg-white text-sm text-slate-500">
            Select a ready backend to view its resource graph here.
          </div>
        )}
      </div>
    </section>
  )
}

function AlertsPanel({
  scans,
  backends,
  kind,
  onFixAlerts,
  onOpenAlert,
  getPullRequest,
}: {
  scans: ResourceScan[]
  backends: StateBackend[]
  kind: AlertKind
  onFixAlerts: (scan: ResourceScan, items: unknown[], kind: AlertKind) => void
  onOpenAlert: (issue: SelectedAlertIssue) => void
  getPullRequest: (scan: ResourceScan, item: unknown, kind: AlertKind) => PullRequestAction | null
}) {
  const [query, setQuery] = useState("")
  const label = kind === "drift" ? "drift alerts" : "policy alerts"
  const groups = getLatestScansByBackend(scans)
    .map(scan => ({ scan, items: kind === "drift" ? scan.driftAlerts : scan.policyAlerts }))
    .filter(group => group.items.length > 0)

  if (!groups.length) return <EmptyState label={`No ${label} found across backend states.`} />

  return (
    <section className="rounded-lg border border-slate-200 bg-white">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b p-4">
        <Input value={query} onChange={event => setQuery(event.target.value)} placeholder={`Search ${label}...`} className="max-w-md" />
      </div>
      <div className="divide-y">
        {groups.map(group => {
          const filteredItems = group.items.filter(item => {
            const alert = asRecord(item)
            const haystack = [
              getAlertTitle(item, kind),
              getAlertResource(item),
              alert.policy_id,
              alert.severity,
              alert.message,
            ].map(value => text(value).toLowerCase()).join(" ")
            return haystack.includes(query.trim().toLowerCase())
          })
          if (!filteredItems.length) return null
          const groupPullRequest = filteredItems
            .map(item => getPullRequest(group.scan, item, kind))
            .find((item): item is PullRequestAction => Boolean(item))
          return (
            <details key={group.scan.scanId} open className="group">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-3 border-b border-slate-200 bg-white px-4 py-3">
                <div className="min-w-0">
                  <span className="font-semibold text-slate-900">{group.scan.backendName || group.scan.backendId}</span>
                  <span className="ml-2 rounded-md border border-red-200 bg-red-50 px-2 py-1 text-xs font-medium text-red-700">
                    {filteredItems.length} active
                  </span>
                  <span className="ml-2 rounded-full border border-slate-200 bg-white px-2.5 py-1 text-xs text-slate-600">
                    {group.items.length} total
                  </span>
                  <p className="mt-1 break-all text-xs text-slate-500">s3://{group.scan.stateBucket}/{group.scan.stateKey}</p>
                </div>
                {groupPullRequest ? (
                  <Button asChild type="button" size="sm" variant="outline" className="gap-2">
                    <a href={groupPullRequest.url} target="_blank" rel="noreferrer" onClick={event => event.stopPropagation()}>
                      <GitPullRequest className="h-4 w-4" />
                      View pull request
                    </a>
                  </Button>
                ) : repositoryForScan(group.scan, backends) ? (
                  <Button
                    type="button"
                    size="sm"
                    className="gap-2"
                    onClick={event => {
                      event.preventDefault()
                      onFixAlerts(group.scan, filteredItems, kind)
                    }}
                  >
                    <Wrench className="h-4 w-4" />
                    Fix All
                  </Button>
                ) : null}
                <span className="text-sm text-slate-500 group-open:hidden">Expand</span>
                <span className="hidden text-sm text-slate-500 group-open:inline">Collapse</span>
              </summary>
              <div className="overflow-x-auto">
                <table className="w-full min-w-[940px] text-left text-sm">
                  <thead className="border-b bg-white text-xs uppercase text-slate-500">
                    <tr>
                      <th className="px-4 py-3">Status</th>
                      <th className="px-4 py-3">Resource</th>
                      <th className="px-4 py-3">Severity</th>
                      <th className="px-4 py-3">Last Detected</th>
                      <th className="px-4 py-3">First Detected</th>
                      <th className="px-4 py-3 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y">
                    {filteredItems.map((item, index) => {
                      const pullRequest = getPullRequest(group.scan, item, kind)
                      const canFix = Boolean(repositoryForScan(group.scan, backends))
                      return (
                        <tr
                          key={`${group.scan.scanId}-${kind}-${index}`}
                          className="align-top hover:bg-slate-50/80 focus-within:bg-slate-50/80"
                        >
                          <td className="px-4 py-4"><StatusBadge>active</StatusBadge></td>
                          <td className="px-4 py-4">
                            <button
                              type="button"
                              onClick={event => {
                                event.stopPropagation()
                                onOpenAlert({ scan: group.scan, item, kind })
                              }}
                              className="block max-w-sm text-left"
                            >
                              <span className="block font-mono text-sm font-semibold text-slate-900 underline-offset-4 hover:underline">
                                {getAlertTitle(item, kind)}
                              </span>
                              <span className="mt-1 block break-all text-xs text-slate-500">{getAlertResource(item)}</span>
                            </button>
                          </td>
                          <td className="px-4 py-4 text-slate-600">{alertSeverity(item, kind)}</td>
                          <td className="px-4 py-4 text-slate-600">{formatDate(group.scan.updatedAt || group.scan.startedAt)}</td>
                          <td className="px-4 py-4 text-slate-600">{formatDate(group.scan.startedAt)}</td>
                          <td className="px-4 py-4 text-right" onClick={event => event.stopPropagation()}>
                            {pullRequest ? (
                              <Button asChild type="button" size="sm" variant="outline" className="gap-2">
                                <a href={pullRequest.url} target="_blank" rel="noreferrer">
                                  <GitPullRequest className="h-4 w-4" />
                                  View pull request
                                </a>
                              </Button>
                            ) : canFix ? (
                              <Button
                                type="button"
                                size="sm"
                                variant="outline"
                                onClick={event => {
                                  event.stopPropagation()
                                  onFixAlerts(group.scan, [item], kind)
                                }}
                                className="gap-2"
                              >
                                <Wrench className="h-4 w-4" />
                                Fix error
                              </Button>
                            ) : null}
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
            </details>
          )
        })}
      </div>
    </section>
  )
}

function ScanHistoryTable({ scans }: { scans: ResourceScan[] }) {
  if (!scans.length) return <EmptyState label="No scan history found." />

  return (
    <section className="rounded-lg border border-slate-200 bg-white">
      <div className="overflow-x-auto">
        <table className="w-full min-w-[980px] text-left text-sm">
          <thead className="border-b border-slate-200 bg-white text-xs uppercase text-slate-500">
            <tr>
              <th className="px-4 py-3">Status</th>
              <th className="px-4 py-3">Backend</th>
              <th className="px-4 py-3">State</th>
              <th className="px-4 py-3">Resources</th>
              <th className="px-4 py-3">Alerts</th>
              <th className="px-4 py-3">Started</th>
              <th className="px-4 py-3">Updated</th>
            </tr>
          </thead>
          <tbody className="divide-y">
            {scans.map(scan => (
              <tr key={scan.scanId} className="align-top hover:bg-slate-50/80">
                <td className="px-4 py-4"><StatusBadge>{scan.status}</StatusBadge></td>
                <td className="px-4 py-4">
                  <p className="font-semibold text-slate-900">{scan.backendName || scan.backendId}</p>
                  <p className="text-xs text-slate-500">{scan.scanId}</p>
                </td>
                <td className="px-4 py-4 break-all text-slate-600">s3://{scan.stateBucket}/{scan.stateKey}</td>
                <td className="px-4 py-4 text-slate-600">{scan.currentResources.length}</td>
                <td className="px-4 py-4 text-slate-600">{scan.driftAlerts.length} drift / {scan.policyAlerts.length} policy</td>
                <td className="px-4 py-4 text-slate-600">{formatDate(scan.startedAt)}</td>
                <td className="px-4 py-4 text-slate-600">{formatDate(scan.updatedAt)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  )
}

function AutoScanPanel({
  backends,
  guards,
  scans,
  selectedBackendId,
  isRunning,
  onSelectedBackendChange,
  onRun,
}: {
  backends: StateBackend[]
  guards: DriftGuard[]
  scans: ResourceScan[]
  selectedBackendId: string
  isRunning: boolean
  onSelectedBackendChange: (backendId: string) => void
  onRun: () => void
}) {
  const selectedBackend = backends.find(backend => backend.backendId === selectedBackendId) ?? null
  const selectedGuard = guards.find(guard => guard.backendId === selectedBackendId) ?? null
  const rows = scans.filter(scan => scan.backendId === selectedBackendId || scan.guardId === selectedGuard?.guardId)

  if (!backends.length) return <EmptyState label="No added state backend found. Add a state backend first." />

  return (
    <section className="grid gap-4 lg:grid-cols-[360px_1fr]">
      <div className="rounded-lg border border-slate-200 bg-white p-5">
        <div className="flex items-center gap-3">
          <CalendarClock className="h-5 w-5 text-slate-800" />
          <div>
            <h2 className="text-base font-semibold text-slate-900">Autoscan</h2>
            <p className="mt-1 text-sm text-slate-500">Choose an added state backend and run a Cloudrift scan.</p>
          </div>
        </div>

        <label className="mt-5 flex flex-col gap-1 text-sm font-medium text-slate-700">
          Added State
          <select
            className="h-9 rounded-lg border border-slate-200 bg-white px-3 text-sm outline-none focus:border-slate-400 focus:ring-[3px] focus:ring-slate-200"
            value={selectedBackendId}
            onChange={event => onSelectedBackendChange(event.target.value)}
          >
            {backends.map(backend => (
              <option key={backend.backendId} value={backend.backendId}>
                {backend.name}
              </option>
            ))}
          </select>
        </label>

        {selectedBackend && (
          <div className="mt-4 rounded-lg border border-slate-200 bg-slate-50 p-3 text-sm text-slate-600">
            <p className="font-medium text-slate-900">{selectedBackend.name}</p>
            <p className="mt-1 break-all">s3://{selectedBackend.bucket}/{selectedBackend.key}</p>
            <p className="mt-1">{selectedBackend.region}</p>
            <p className="mt-1 break-all">{selectedBackend.repository?.fullName || "No repository connected"}</p>
          </div>
        )}

        <Button
          type="button"
          onClick={onRun}
          disabled={!selectedBackend || !selectedBackend.repository?.fullName || isRunning}
          className="mt-4 w-full gap-2"
          title={!selectedBackend?.repository?.fullName ? "Connect this state backend to an installed GitHub repository first" : undefined}
        >
          <Play className="h-4 w-4" />
          {isRunning ? "Starting Autoscan" : "Run Autoscan"}
        </Button>
      </div>

      <section className="rounded-lg border border-slate-200 bg-white">
        <div className="border-b p-4">
          <h2 className="text-base font-semibold text-slate-900">Autoscan History</h2>
          <p className="mt-1 text-sm text-slate-500">Recent scans for the selected added state.</p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[820px] text-left text-sm">
            <thead className="border-b border-slate-200 bg-white text-xs uppercase text-slate-500">
              <tr>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3">Backend</th>
                <th className="px-4 py-3">Alerts</th>
                <th className="px-4 py-3">Started</th>
                <th className="px-4 py-3">Updated</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {rows.map(scan => (
                <tr key={scan.scanId} className="hover:bg-slate-50/80">
                  <td className="px-4 py-4"><StatusBadge>{scan.status}</StatusBadge></td>
                  <td className="px-4 py-4">
                    <p className="font-semibold text-slate-900">{scan.backendName || scan.backendId}</p>
                    <p className="break-all text-xs text-slate-500">s3://{scan.stateBucket}/{scan.stateKey}</p>
                  </td>
                  <td className="px-4 py-4 text-slate-600">{scan.driftAlerts.length} drift / {scan.policyAlerts.length} policy</td>
                  <td className="px-4 py-4 text-slate-600">{formatDate(scan.startedAt)}</td>
                  <td className="px-4 py-4 text-slate-600">{formatDate(scan.updatedAt)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {rows.length === 0 && <p className="p-4 text-sm text-slate-500">No autoscans for this state yet.</p>}
        </div>
      </section>
    </section>
  )
}

export default function ResourceCatalogPage() {
  const auth = useAuth()
  const navigate = useNavigate()
  const requestRepositoryChat = useWebAppStore(state => state.requestRepositoryChat)
  const sessions = useWebAppStore(state => state.sessions)
  const catalog = useWebAppStore(state => state.resourceCatalog)
  const isCatalogLoading = useWebAppStore(state => state.isResourceCatalogLoading)
  const loadResourceCatalog = useWebAppStore(state => state.loadResourceCatalog)
  const setResourceCatalog = useWebAppStore(state => state.setResourceCatalog)
  const [activeTab, setActiveTab] = useState<CatalogTab>("resources")
  const [selectedAutoScanBackendId, setSelectedAutoScanBackendId] = useState("")
  const [isRunningAutoScan, setIsRunningAutoScan] = useState(false)
  const [openingGraphBackendId, setOpeningGraphBackendId] = useState<string | null>(null)
  const [embeddedGraph, setEmbeddedGraph] = useState<EmbeddedGraph | null>(null)
  const [selectedResourceRow, setSelectedResourceRow] = useState<ResourceRow | null>(null)
  const [selectedAlertIssue, setSelectedAlertIssue] = useState<SelectedAlertIssue | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const { backends, stateResources, guards, scans } = catalog

  const refresh = useCallback(async (options: { force?: boolean } = {}) => {
    const idToken = auth.user?.id_token
    if (!idToken) return
    setError(null)
    try {
      const loadedCatalog = await loadResourceCatalog(idToken, options)
      setSelectedAutoScanBackendId(current => current || loadedCatalog.backends[0]?.backendId || "")
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Failed to load resource catalog")
    }
  }, [auth.user?.id_token, loadResourceCatalog])

  useEffect(() => {
    void refresh()
  }, [refresh])

  const latestScans = useMemo(() => getLatestScansByBackend(scans), [scans])
  const resourceRows = useMemo(() => buildResourceRows(scans, backends, stateResources), [backends, scans, stateResources])
  const driftCount = latestScans.reduce((sum, scan) => sum + scan.driftAlerts.length, 0)
  const policyCount = latestScans.reduce((sum, scan) => sum + scan.policyAlerts.length, 0)

  const handleRunAutoScan = useCallback(async () => {
    const idToken = auth.user?.id_token
    const backend = backends.find(item => item.backendId === selectedAutoScanBackendId)
    if (!idToken) {
      setError("Sign in before running Autoscan")
      return
    }
    if (!backend) {
      setError("Choose an added state backend before running Autoscan")
      return
    }
    if (!backend.repository?.fullName) {
      setError("Connect this state backend to an installed GitHub repository before running Autoscan")
      return
    }
    setIsRunningAutoScan(true)
    setError(null)
    setMessage(null)
    try {
      const existingGuard = guards.find(guard => guard.backendId === backend.backendId)
      const savedGuard = await saveDriftGuard(
        {
          guardId: existingGuard?.guardId,
          name: existingGuard?.name || `Autoscan - ${backend.name}`,
          backendId: backend.backendId,
          repository: backend.repository.fullName,
          frequency: "manual",
          email: String((auth.user?.profile as Record<string, unknown> | undefined)?.email || ""),
          enabled: true,
        },
        idToken
      )
      setResourceCatalog(current => ({
        ...current,
        guards: [savedGuard, ...current.guards.filter(item => item.guardId !== savedGuard.guardId)],
      }), idToken)
      const result = await runDriftGuard(savedGuard.guardId, idToken)
      if (result.scan) {
        setResourceCatalog(current => ({
          ...current,
          scans: [result.scan!, ...current.scans],
          guards: current.guards.map(guard =>
            guard.guardId === savedGuard.guardId
              ? { ...guard, lastScanId: result.scan!.scanId, lastRunAt: result.scan!.startedAt }
              : guard
          ),
        }), idToken)
      }
      setMessage(result.skipped ? `Autoscan skipped: ${result.reason}` : "Autoscan started")
    } catch (runError) {
      setError(runError instanceof Error ? runError.message : "Failed to run Autoscan")
    } finally {
      setIsRunningAutoScan(false)
    }
  }, [auth.user?.id_token, auth.user?.profile, backends, guards, selectedAutoScanBackendId, setResourceCatalog])

  const handleLoadGraph = useCallback(
    async (backend: StateBackend) => {
      const idToken = auth.user?.id_token
      if (!idToken) {
        setError("Sign in before loading a resource graph")
        return
      }
      setOpeningGraphBackendId(backend.backendId)
      setError(null)
      try {
        const graph = await getStateBackendGraphUrl(backend.backendId, idToken)
        setEmbeddedGraph({
          backendId: backend.backendId,
          backendName: backend.name,
          url: graph.url,
          generatedAt: graph.graphGeneratedAt ?? backend.graphGeneratedAt,
          resourceCount: graph.graphResourceCount ?? backend.graphResourceCount,
        })
      } catch (graphError) {
        setError(graphError instanceof Error ? graphError.message : "Failed to load resource graph")
      } finally {
        setOpeningGraphBackendId(null)
      }
    },
    [auth.user?.id_token]
  )

  const openFixChat = useCallback(
    (repository: SelectedRepository | null, stateBackend: SelectedStateBackend | null, prompt: string) => {
      if (!repository) {
        setError("Connect this state backend to an installed GitHub repository before fixing errors.")
        return
      }
      if (!stateBackend) {
        setError("Connect this issue to a state backend before fixing errors.")
        return
      }
      requestRepositoryChat(repository, prompt, stateBackend)
      navigate("/")
    },
    [navigate, requestRepositoryChat]
  )

  const handleFixResource = useCallback(
    (row: ResourceRow) => {
      if (!row.repository) {
        openFixChat(null, null, "")
        return
      }
      const kind = rowFixKind(row)
      const alerts = rowFixAlerts(row)
      openFixChat(
        row.repository,
        row.stateBackend,
        buildFixPrompt({
          kind,
          scan: row.scan,
          repository: row.repository as SelectedRepository,
          resource: row.resource,
          after: row.after,
          alerts,
        })
      )
    },
    [openFixChat]
  )

  const handleFixAlerts = useCallback(
    (scan: ResourceScan, items: unknown[], kind: AlertKind) => {
      const repository = repositoryForScan(scan, backends)
      const stateBackend = stateBackendForScan(scan, backends)
      if (!repository) {
        openFixChat(null, null, "")
        return
      }
      openFixChat(
        repository,
        stateBackend,
        buildFixPrompt({
          kind,
          scan,
          repository: repository as SelectedRepository,
          alerts: items,
        })
      )
    },
    [backends, openFixChat]
  )

  const getResourcePullRequest = useCallback(
    (row: ResourceRow) =>
      findIssuePullRequest({
        sessions,
        repository: row.repository,
        scan: row.scan,
        tokens: resourceTokens(row),
      }),
    [sessions]
  )

  const getAlertPullRequest = useCallback(
    (scan: ResourceScan, item: unknown, kind: AlertKind) =>
      findIssuePullRequest({
        sessions,
        repository: repositoryForScan(scan, backends),
        scan,
        tokens: alertFixTokens(item, kind),
      }),
    [backends, sessions]
  )

  return (
    <main className="min-h-screen bg-white">
      <header className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex max-w-[1800px] flex-wrap items-center justify-between gap-4 px-6 py-5">
          <div>
            <div className="flex items-center gap-2 text-sm font-medium text-slate-500">
              <Database className="h-4 w-4" />
              Cloudrift
            </div>
            <h1 className="mt-1 text-2xl font-semibold text-slate-950">Resource Catalog</h1>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button asChild type="button" variant="outline" className="gap-2">
              <Link to="/settings">Manage State Backends</Link>
            </Button>
            <Button type="button" onClick={() => void refresh({ force: true })} disabled={isCatalogLoading} className="gap-2">
              <RefreshCw className={`h-4 w-4 ${isCatalogLoading ? "animate-spin" : ""}`} />
              Reload
            </Button>
          </div>
        </div>
      </header>

      <section className="mx-auto flex max-w-[1800px] flex-col gap-4 px-6 py-5">
        {message && <p className="rounded-md border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-700">{message}</p>}
        {error && <p className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</p>}

        <div className="grid gap-3 md:grid-cols-5">
          <MetricCard label="Connected Resources" value={resourceRows.length} icon={<Boxes className="h-4 w-4" />} />
          <MetricCard label="State Backends" value={backends.length} icon={<Database className="h-4 w-4" />} />
          <MetricCard label="Drift Alerts" value={driftCount} icon={<AlertTriangle className="h-4 w-4" />} />
          <MetricCard label="Policy Alerts" value={policyCount} icon={<ShieldAlert className="h-4 w-4" />} />
          <MetricCard label="Scans" value={scans.length} icon={<Clock3 className="h-4 w-4" />} />
        </div>

        <CloudriftAnalyticsChart rows={resourceRows} scans={scans} backends={backends} />

        <nav className="flex flex-wrap gap-2 border-b border-slate-200">
          {tabs.map(tab => {
            const Icon = tab.icon
            const isActive = activeTab === tab.value
            return (
              <button
                key={tab.value}
                type="button"
                onClick={() => setActiveTab(tab.value)}
                className={`flex items-center gap-2 border-b-2 px-4 py-3 text-sm font-semibold transition ${
                  isActive
                    ? "border-slate-950 text-slate-950"
                    : "border-transparent text-slate-500 hover:border-slate-300 hover:text-slate-900"
                }`}
              >
                <Icon className="h-4 w-4" />
                {tab.label}
              </button>
            )
          })}
        </nav>

        {activeTab === "resources" && (
          <ResourcesTable
            rows={resourceRows}
            onFixResource={handleFixResource}
            onOpenResource={setSelectedResourceRow}
            getPullRequest={getResourcePullRequest}
          />
        )}
        {activeTab === "visualize" && (
          <ResourceGraphViewer
            backends={backends}
            openingBackendId={openingGraphBackendId}
            embeddedGraph={embeddedGraph}
            onLoadGraph={backend => void handleLoadGraph(backend)}
          />
        )}
        {activeTab === "state" && <StateHistoryTable backends={backends} scans={scans} />}
        {activeTab === "autoscan" && (
          <AutoScanPanel
            backends={backends}
            guards={guards}
            scans={scans}
            selectedBackendId={selectedAutoScanBackendId}
            isRunning={isRunningAutoScan}
            onSelectedBackendChange={setSelectedAutoScanBackendId}
            onRun={() => void handleRunAutoScan()}
          />
        )}
        {activeTab === "drift" && (
          <AlertsPanel
            scans={scans}
            backends={backends}
            kind="drift"
            onFixAlerts={handleFixAlerts}
            onOpenAlert={setSelectedAlertIssue}
            getPullRequest={getAlertPullRequest}
          />
        )}
        {activeTab === "policy" && (
          <AlertsPanel
            scans={scans}
            backends={backends}
            kind="policy"
            onFixAlerts={handleFixAlerts}
            onOpenAlert={setSelectedAlertIssue}
            getPullRequest={getAlertPullRequest}
          />
        )}
        {activeTab === "scans" && <ScanHistoryTable scans={scans} />}

        <ResourceDetailsDialog
          row={selectedResourceRow}
          pullRequest={selectedResourceRow ? getResourcePullRequest(selectedResourceRow) : null}
          onOpenChange={open => {
            if (!open) setSelectedResourceRow(null)
          }}
          onFixResource={handleFixResource}
        />

        <AlertIssueDetailsDialog
          issue={selectedAlertIssue}
          pullRequest={selectedAlertIssue ? getAlertPullRequest(selectedAlertIssue.scan, selectedAlertIssue.item, selectedAlertIssue.kind) : null}
          canFix={Boolean(selectedAlertIssue && repositoryForScan(selectedAlertIssue.scan, backends))}
          onOpenChange={open => {
            if (!open) setSelectedAlertIssue(null)
          }}
          onFixAlert={(scan, item, kind) => handleFixAlerts(scan, [item], kind)}
        />

        {!isCatalogLoading && scans.length === 0 && (
          <div className="rounded-lg border border-slate-200 bg-white p-5 text-sm text-slate-600">
            <div className="flex items-center gap-2 font-medium text-slate-900">
              <CheckCircle2 className="h-4 w-4" />
              Waiting for Cloudrift data
            </div>
            <p className="mt-2">Run scans from the Scan tab to populate this catalog.</p>
          </div>
        )}
      </section>
    </main>
  )
}
