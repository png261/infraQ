import { fireEvent, render, screen, waitFor, within } from "@testing-library/react"
import { MemoryRouter } from "react-router-dom"
import { beforeEach, describe, expect, it, vi } from "vitest"
import { AppSidebar } from "@/components/layout/AppSidebar"
import ResourceCatalogPage from "@/routes/ResourceCatalogPage"
import PullRequestsPage from "@/routes/PullRequestsPage"
import SettingsPage from "@/routes/SettingsPage"
import AppRoutes from "@/routes"
import { useWebAppStore } from "@/stores/webAppStore"

const authState = vi.hoisted(() => ({
  isAuthenticated: true,
  user: {
    access_token: "dev-access-token",
    id_token: "dev-id-token",
    profile: {
      email: "dev@gmail.com",
      sub: "dev-user",
    },
  },
  signIn: vi.fn(),
  signOut: vi.fn(),
  isLoading: false,
  error: null,
  token: "dev-id-token",
}))

const storeActions = vi.hoisted(() => ({
  requestNewChat: vi.fn(),
  requestRepositoryChat: vi.fn(),
  setActiveSessionId: vi.fn(),
  deleteChatSession: vi.fn(),
  hydrateChatSessions: vi.fn(async () => ({ sessions: [], activeSessionId: "" })),
  hydrateUserConfig: vi.fn(async () => undefined),
  persistSelectedRepository: vi.fn(async () => undefined),
  loadPullRequests: vi.fn(),
  loadResourceCatalog: vi.fn(),
  setResourceCatalog: vi.fn(),
}))

const resourceMocks = vi.hoisted(() => ({
  listStateBackends: vi.fn(),
  listStateBackendResources: vi.fn(),
  listResourceScans: vi.fn(),
  listDriftGuards: vi.fn(),
  listAwsCredentials: vi.fn(),
  createStateBackend: vi.fn(),
  deleteStateBackend: vi.fn(),
  deleteAwsCredential: vi.fn(),
  listS3Buckets: vi.fn(),
  getStateBackendGraphUrl: vi.fn(),
  saveDriftGuard: vi.fn(),
  runDriftGuard: vi.fn(),
}))

const installedRepositories = vi.hoisted(() => ({
  repositories: [
    {
      owner: "png261",
      name: "hcp-terraform",
      fullName: "png261/hcp-terraform",
      defaultBranch: "main",
    },
  ],
  isLoading: false,
  error: null,
}))

vi.mock("@/hooks/useAuth", () => ({
  useAuth: () => authState,
}))

vi.mock("@/components/chat/ChatInterface", () => ({
  default: () => <div data-testid="chat-interface">Chat Interface</div>,
}))

vi.mock("@/stores/webAppStore", async () => {
  const { create } = await vi.importActual<typeof import("zustand")>("zustand")
  type MockCatalog = {
    backends: Array<{ backendId: string }>
    stateResources: unknown[]
    scans: unknown[]
    guards: unknown[]
    credentials: unknown[]
  }
  type MockState = Record<string, unknown> & {
    resourceCatalog: MockCatalog
    resourceCatalogLoadedFor: string
    resourceCatalogFetchedAt: number
    isResourceCatalogLoading: boolean
  }
  const selectedRepository = {
    owner: "png261",
    name: "hcp-terraform",
    fullName: "png261/hcp-terraform",
    defaultBranch: "main",
  }
  const initialSessions = [
    {
      id: "session-1",
      name: "Dev chat",
      history: [],
      startDate: "2026-05-15T01:00:00.000Z",
      endDate: "2026-05-15T01:00:00.000Z",
      repository: null,
      pullRequest: null,
    },
    {
      id: "session-pr-42",
      name: "Fix drift",
      history: [
        {
          role: "user",
          content: "Fix policy compliance issue. Scan ID: scan-prod. State backend: s3://tf-prod-state/env/prod/terraform.tfstate. Resource: aws_s3_bucket.logs. Policy: S3 encryption required.",
          timestamp: "2026-05-15T01:20:00.000Z",
        },
      ],
      startDate: "2026-05-15T01:20:00.000Z",
      endDate: "2026-05-15T01:25:00.000Z",
      repository: selectedRepository,
      pullRequest: {
        number: 42,
        url: "https://github.com/png261/hcp-terraform/pull/42",
      },
    },
  ]
  const emptyCatalog = () => ({
    backends: [],
    stateResources: [],
    scans: [],
    guards: [],
    credentials: [],
  })
  const useWebAppStore = create<MockState>((set, get) => ({
      sessions: [
        ...initialSessions,
      ],
      activeSessionId: "session-1",
      selectedRepository,
      pullRequestsByKey: {},
      resourceCatalog: emptyCatalog(),
      resourceCatalogLoadedFor: "",
      resourceCatalogFetchedAt: 0,
      isResourceCatalogLoading: false,
      requestNewChat: storeActions.requestNewChat,
      requestRepositoryChat: storeActions.requestRepositoryChat,
      setActiveSessionId: storeActions.setActiveSessionId,
      deleteChatSession: storeActions.deleteChatSession,
      hydrateChatSessions: storeActions.hydrateChatSessions,
      hydrateUserConfig: storeActions.hydrateUserConfig,
      persistSelectedRepository: storeActions.persistSelectedRepository,
      loadPullRequests: storeActions.loadPullRequests,
      setResourceCatalog: (updater: MockCatalog | ((current: MockCatalog) => MockCatalog), idToken?: string) => {
        storeActions.setResourceCatalog(updater, idToken)
        set((state: MockState) => ({
          resourceCatalog: typeof updater === "function" ? updater(state.resourceCatalog) : updater,
          resourceCatalogLoadedFor: idToken ?? state.resourceCatalogLoadedFor,
          resourceCatalogFetchedAt: Date.now(),
        }))
      },
      loadResourceCatalog: async (idToken: string, options: { force?: boolean } = {}) => {
        storeActions.loadResourceCatalog(idToken, options)
        const state = get()
        if (!options.force && state.resourceCatalogLoadedFor === idToken) {
          return state.resourceCatalog
        }
        set({ isResourceCatalogLoading: true })
        const [backends, scans, guards, credentialsResponse] = await Promise.all([
          resourceMocks.listStateBackends(idToken),
          resourceMocks.listResourceScans(idToken),
          resourceMocks.listDriftGuards(idToken),
          resourceMocks.listAwsCredentials(idToken),
        ])
        const stateResources = (
          await Promise.all(backends.map((item: { backendId: string }) => resourceMocks.listStateBackendResources(item.backendId, idToken)))
        ).flat()
        const resourceCatalog = {
          backends,
          stateResources,
          scans,
          guards,
          credentials: credentialsResponse.credentials,
        }
        set({
          resourceCatalog,
          resourceCatalogLoadedFor: idToken,
          resourceCatalogFetchedAt: Date.now(),
          isResourceCatalogLoading: false,
        })
        return resourceCatalog
      },
    }))
  return { useWebAppStore }
})

vi.mock("@/hooks/useInstalledRepositories", () => ({
  useInstalledRepositories: () => installedRepositories,
}))

vi.mock("@/components/github/InstalledRepositoryCombobox", () => ({
  InstalledRepositoryCombobox: ({
    repositories,
    value,
    onValueChange,
  }: {
    repositories: Array<{ fullName: string }>
    value: string
    onValueChange: (value: string) => void
  }) => (
    <select
      aria-label="GitHub Repository"
      value={value}
      onChange={event => onValueChange(event.target.value)}
    >
      {repositories.map(repository => (
        <option key={repository.fullName} value={repository.fullName}>
          {repository.fullName}
        </option>
      ))}
    </select>
  ),
}))

vi.mock("@/services/resourcesService", async importOriginal => {
  const actual = await importOriginal<typeof import("@/services/resourcesService")>()
  return {
    ...actual,
    listStateBackends: resourceMocks.listStateBackends,
    listStateBackendResources: resourceMocks.listStateBackendResources,
    listResourceScans: resourceMocks.listResourceScans,
    listDriftGuards: resourceMocks.listDriftGuards,
    listAwsCredentials: resourceMocks.listAwsCredentials,
    createStateBackend: resourceMocks.createStateBackend,
    deleteStateBackend: resourceMocks.deleteStateBackend,
    deleteAwsCredential: resourceMocks.deleteAwsCredential,
    listS3Buckets: resourceMocks.listS3Buckets,
    getStateBackendGraphUrl: resourceMocks.getStateBackendGraphUrl,
    saveDriftGuard: resourceMocks.saveDriftGuard,
    runDriftGuard: resourceMocks.runDriftGuard,
  }
})

vi.mock("@/lib/agentcore-client", () => ({
  AgentCoreClient: vi.fn().mockImplementation(function AgentCoreClient() {
    return {
      githubAction: vi.fn(async () => ({
        repositories: [
          {
            owner: "png261",
            name: "hcp-terraform",
            fullName: "png261/hcp-terraform",
            defaultBranch: "main",
          },
        ],
        accounts: [{ login: "png261" }],
      })),
    }
  }),
}))

const repository = {
  owner: "png261",
  name: "hcp-terraform",
  fullName: "png261/hcp-terraform",
  defaultBranch: "main",
}

const backend = {
  backendId: "backend-prod",
  name: "Production state",
  bucket: "tf-prod-state",
  key: "env/prod/terraform.tfstate",
  region: "ap-southeast-1",
  service: "s3",
  credentialId: "cred-1",
  credentialName: "Dev AWS",
  repository,
  graphBucket: "graphs",
  graphKey: "backend-prod.png",
  graphGeneratedAt: "2026-05-15T01:00:00.000Z",
  graphResourceCount: 2,
  createdAt: "2026-05-15T01:00:00.000Z",
  updatedAt: "2026-05-15T01:00:00.000Z",
}

const scan = {
  scanId: "scan-prod",
  backendId: "backend-prod",
  backendName: "Production state",
  stateBucket: "tf-prod-state",
  stateKey: "env/prod/terraform.tfstate",
  stateRegion: "ap-southeast-1",
  service: "s3",
  status: "SUCCEEDED",
  startedAt: "2026-05-15T01:05:00.000Z",
  updatedAt: "2026-05-15T01:06:00.000Z",
  driftAlerts: [
    {
      resource_address: "aws_s3_bucket.logs",
      resource_type: "aws_s3_bucket",
      resource_id: "prod-logs",
      resource_name: "prod-logs",
      severity: "high",
      message: "Bucket tags drifted",
      missing: false,
      diffs: {
        acl: ["<planned>", "<actual>"],
      },
      extra_attributes: {
        "tags.CloudriftDrift": "manual-console-change-20260510",
      },
    },
    {
      resource_address: "aws_instance.app",
      resource_type: "aws_instance",
      resource_id: "i-0123456789abcdef0",
      resource_name: "app-server",
      severity: "medium",
      message: "Instance shape drifted",
      missing: false,
      diffs: {
        instance_type: ["t3.micro", "t3.small"],
      },
      actual_attributes: {
        instance_type: "t3.small",
      },
    },
  ],
  policyAlerts: [
    {
      resource_address: "aws_s3_bucket.logs",
      policy_name: "S3 encryption required",
      severity: "critical",
      message: "Default encryption is missing",
    },
  ],
  currentResources: [
    {
      address: "aws_s3_bucket.logs",
      type: "aws_s3_bucket",
      change: {
        after: {
          bucket: "prod-logs",
          arn: "arn:aws:s3:::prod-logs",
        },
      },
    },
  ],
  repository,
}

const stateResources = [
  {
    backendId: "backend-prod",
    backendName: "Production state",
    stateBucket: "tf-prod-state",
    stateKey: "env/prod/terraform.tfstate",
    stateRegion: "ap-southeast-1",
    service: "s3",
    repository,
    address: "aws_s3_bucket.logs",
    type: "aws_s3_bucket",
    name: "logs",
    values: {
      bucket: "prod-logs",
      arn: "arn:aws:s3:::prod-logs",
    },
    updatedAt: "2026-05-15T01:00:00.000Z",
  },
  {
    backendId: "backend-prod",
    backendName: "Production state",
    stateBucket: "tf-prod-state",
    stateKey: "env/prod/terraform.tfstate",
    stateRegion: "ap-southeast-1",
    service: "s3",
    repository,
    address: "aws_instance.app",
    type: "aws_instance",
    name: "app",
    values: {
      id: "i-0123456789abcdef0",
      tags: { Name: "app-server" },
    },
    updatedAt: "2026-05-15T01:00:00.000Z",
  },
]

function renderWithRouter(ui: React.ReactElement, initialEntries = ["/"]) {
  return render(<MemoryRouter initialEntries={initialEntries}>{ui}</MemoryRouter>)
}

describe("authenticated app functional coverage", () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          githubAppInstallUrl: "https://github.com/apps/appleai-codes/installations/new",
          agentRuntimeArn: "arn:aws:bedrock-agentcore:ap-southeast-1:123456789012:runtime/test",
          awsRegion: "ap-southeast-1",
        }),
      })
    )
    useWebAppStore.setState({
      sessions: [
        {
          id: "session-1",
          name: "Dev chat",
          history: [],
          startDate: "2026-05-15T01:00:00.000Z",
          endDate: "2026-05-15T01:00:00.000Z",
          repository: null,
          pullRequest: null,
        },
        {
          id: "session-pr-42",
          name: "Fix drift",
          history: [
            {
              role: "user",
              content: "Fix policy compliance issue. Scan ID: scan-prod. State backend: s3://tf-prod-state/env/prod/terraform.tfstate. Resource: aws_s3_bucket.logs. Policy: S3 encryption required.",
              timestamp: "2026-05-15T01:20:00.000Z",
            },
          ],
          startDate: "2026-05-15T01:20:00.000Z",
          endDate: "2026-05-15T01:25:00.000Z",
          repository,
          pullRequest: {
            number: 42,
            url: "https://github.com/png261/hcp-terraform/pull/42",
          },
        },
      ],
      activeSessionId: "session-1",
      selectedRepository: repository,
      resourceCatalog: {
        backends: [],
        stateResources: [],
        scans: [],
        guards: [],
        credentials: [],
      },
      resourceCatalogLoadedFor: "",
      resourceCatalogFetchedAt: 0,
      isResourceCatalogLoading: false,
    })
    resourceMocks.listStateBackends.mockResolvedValue([backend])
    resourceMocks.listStateBackendResources.mockImplementation((backendId: string) =>
      Promise.resolve(backendId === "backend-prod" ? stateResources : [])
    )
    resourceMocks.listResourceScans.mockResolvedValue([scan])
    resourceMocks.listDriftGuards.mockResolvedValue([
      {
        guardId: "guard-prod",
        name: "Autoscan - Production state",
        backendId: "backend-prod",
        repository: "png261/hcp-terraform",
        frequency: "manual",
        email: "dev@gmail.com",
        enabled: true,
        lastScanId: "scan-prod",
        lastRunAt: "2026-05-15T01:05:00.000Z",
        createdAt: "2026-05-15T01:00:00.000Z",
        updatedAt: "2026-05-15T01:06:00.000Z",
      },
    ])
    resourceMocks.listAwsCredentials.mockResolvedValue({
      activeCredentialId: "cred-1",
      credentials: [
        {
          configured: true,
          credentialId: "cred-1",
          name: "Dev AWS",
          accountId: "123456789012",
          region: "ap-southeast-1",
        },
      ],
    })
    resourceMocks.createStateBackend.mockResolvedValue({
      ...backend,
      backendId: "backend-new",
      name: "New production state",
      bucket: "tf-new-state",
      key: "env/new/terraform.tfstate",
    })
    resourceMocks.deleteStateBackend.mockResolvedValue({
      backendId: "backend-prod",
      deletedScans: 1,
      deletedDriftGuards: 1,
      deletedTerraformJobs: 0,
    })
    resourceMocks.listS3Buckets.mockResolvedValue([
      { name: "tf-new-state", createdAt: "2026-05-14T01:00:00.000Z" },
    ])
    resourceMocks.getStateBackendGraphUrl.mockResolvedValue({
      url: "https://example.com/graph.png",
      expiresIn: 300,
    })
    resourceMocks.saveDriftGuard.mockResolvedValue({
      guardId: "guard-prod",
      name: "Autoscan - Production state",
      backendId: "backend-prod",
      repository: "png261/hcp-terraform",
      frequency: "manual",
      email: "dev@gmail.com",
      enabled: true,
      createdAt: "2026-05-15T01:00:00.000Z",
      updatedAt: "2026-05-15T01:06:00.000Z",
    })
    resourceMocks.runDriftGuard.mockResolvedValue({
      scan: {
        ...scan,
        scanId: "scan-autoscan",
        startedAt: "2026-05-15T01:10:00.000Z",
        updatedAt: "2026-05-15T01:11:00.000Z",
      },
    })
    storeActions.loadPullRequests.mockResolvedValue([
      {
        repository: "png261/hcp-terraform",
        number: 42,
        title: "Fix Terraform drift",
        state: "open",
        url: "https://github.com/png261/hcp-terraform/pull/42",
        author: "dev",
        headBranch: "fix/drift",
        baseBranch: "main",
        checkStatus: "success",
        createdAt: "2026-05-15T01:20:00.000Z",
        githubUpdatedAt: "2026-05-15T01:25:00.000Z",
        labels: ["cloudrift"],
        comments: 2,
        reactions: { total: 3 },
        changedFiles: 1,
        additions: 12,
        deletions: 4,
      },
      {
        repository: "png261/hcp-terraform",
        number: 41,
        title: "Old closed change",
        state: "closed",
        url: "https://github.com/png261/hcp-terraform/pull/41",
        author: "dev",
        headBranch: "old/change",
        baseBranch: "main",
        checkConclusion: "failure",
        createdAt: "2026-05-14T01:20:00.000Z",
        closedAt: "2026-05-14T02:20:00.000Z",
        changedFiles: 2,
        additions: 3,
        deletions: 8,
      },
    ])
  })

  it("renders a logged-in dev account, chat route, and authenticated navigation", async () => {
    renderWithRouter(
      <div className="lg:flex">
        <AppSidebar />
        <AppRoutes />
      </div>
    )

    expect(await screen.findByTestId("chat-interface")).toBeInTheDocument()
    expect(screen.getByText("dev@gmail.com")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: /Resource Catalog/i })).toBeInTheDocument()
    expect(screen.getByRole("link", { name: /Pull Requests/i })).toBeInTheDocument()
    expect(screen.getByRole("link", { name: /Settings/i })).toBeInTheDocument()
    expect(screen.queryByText(/Please sign in/i)).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole("link", { name: /Resource Catalog/i }))

    expect(await screen.findByRole("heading", { name: "Resource Catalog" })).toBeInTheDocument()
    expect(resourceMocks.listStateBackends).toHaveBeenCalledWith("dev-id-token")
  })

  it("covers resource catalog browsing, filtering, graph, autoscan, alerts, and fix-chat handoff", async () => {
    renderWithRouter(<ResourceCatalogPage />, ["/resource-catalog"])

    expect(await screen.findByRole("heading", { name: "Resource Catalog" })).toBeInTheDocument()
    expect(screen.getByText("Connected Resources")).toBeInTheDocument()
    expect(await screen.findByText("prod-logs")).toBeInTheDocument()
    expect(screen.getByText("aws_s3_bucket.logs")).toBeInTheDocument()
    expect(screen.getByText("app-server")).toBeInTheDocument()
    expect(resourceMocks.listStateBackendResources).toHaveBeenCalledWith("backend-prod", "dev-id-token")
    expect(screen.getAllByText("drifted").length).toBeGreaterThan(0)

    fireEvent.change(screen.getByPlaceholderText("Search resources..."), {
      target: { value: "no-match" },
    })
    expect(screen.getByText("No resources match that search.")).toBeInTheDocument()
    fireEvent.change(screen.getByPlaceholderText("Search resources..."), {
      target: { value: "prod-logs" },
    })
    expect(screen.getByText("prod-logs")).toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: /prod-logs/i }))
    const resourceDialog = screen.getByRole("dialog", { name: /prod-logs/i })
    expect(within(resourceDialog).getByText("Resource Identity")).toBeInTheDocument()
    expect(within(resourceDialog).getByText("State Backend")).toBeInTheDocument()
    expect(within(resourceDialog).getByText("Current State")).toBeInTheDocument()
    expect(within(resourceDialog).getByText("Drift Findings (1)")).toBeInTheDocument()
    expect(within(resourceDialog).getByText("Policy Findings (1)")).toBeInTheDocument()
    expect(within(resourceDialog).getByText("bucket")).toBeInTheDocument()
    expect(within(resourceDialog).getByText("arn")).toBeInTheDocument()
    expect(within(resourceDialog).getByText("Drift Visualization")).toBeInTheDocument()
    expect(within(resourceDialog).getByText("Attribute")).toBeInTheDocument()
    expect(within(resourceDialog).getByText("Expected (Terraform)")).toBeInTheDocument()
    expect(within(resourceDialog).getByText("Actual (AWS)")).toBeInTheDocument()
    expect(within(resourceDialog).getAllByText("Not returned by Cloudrift").length).toBeGreaterThan(0)
    expect(within(resourceDialog).getByText("tags.CloudriftDrift")).toBeInTheDocument()
    expect(within(resourceDialog).queryByText("<planned>")).not.toBeInTheDocument()
    expect(within(resourceDialog).queryByText("<actual>")).not.toBeInTheDocument()
    expect(within(resourceDialog).getAllByText("S3 encryption required").length).toBeGreaterThan(0)
    fireEvent.click(within(resourceDialog).getAllByRole("button", { name: "Close" })[0])

    expect(screen.getByRole("link", { name: /View pull request/i })).toHaveAttribute(
      "href",
      "https://github.com/png261/hcp-terraform/pull/42"
    )
    expect(screen.queryByRole("button", { name: /Fix error/i })).not.toBeInTheDocument()
    fireEvent.change(screen.getByPlaceholderText("Search resources..."), {
      target: { value: "app-server" },
    })
    fireEvent.click(screen.getAllByRole("button", { name: /Fix drift/i })[0])
    expect(storeActions.requestRepositoryChat).toHaveBeenCalledWith(
      repository,
      expect.stringContaining("State backend: s3://tf-prod-state/env/prod/terraform.tfstate"),
      expect.objectContaining({
        backendId: "backend-prod",
        repository,
      })
    )
    const resourceFixPrompt = storeActions.requestRepositoryChat.mock.calls.at(-1)?.[1] as string
    expect(resourceFixPrompt).toContain("Fix only this issue context:")
    expect(resourceFixPrompt).toContain("Resource address: aws_instance.app")
    expect(resourceFixPrompt).toContain("Issue type: drift")
    expect(resourceFixPrompt).toContain("Kind: drift")
    expect(resourceFixPrompt).toContain("Drift detail:")
    expect(resourceFixPrompt).toContain("Resource type: aws_instance")
    expect(resourceFixPrompt).toContain("Attribute diffs:")
    expect(resourceFixPrompt).toContain("Attribute | Expected (Terraform) | Actual (AWS)")
    expect(resourceFixPrompt).toContain("instance_type:")
    expect(resourceFixPrompt).toContain("Expected (Terraform): t3.micro")
    expect(resourceFixPrompt).toContain("Actual (AWS): t3.small")
    expect(resourceFixPrompt).toContain("Change needed:")
    expect(resourceFixPrompt).not.toContain("Kind: policy")
    expect(resourceFixPrompt).not.toContain("S3 encryption required")
    expect(resourceFixPrompt).not.toContain("```json")
    expect(resourceFixPrompt).not.toContain("rawResult")

    fireEvent.click(screen.getByRole("button", { name: "Visualize" }))
    expect(screen.getByText("Resource Graph Viewer")).toBeInTheDocument()
    expect(screen.getByText("Select a ready backend to view its resource graph here.")).toBeInTheDocument()
    fireEvent.click(screen.getByRole("button", { name: /View graph/i }))
    await waitFor(() => expect(resourceMocks.getStateBackendGraphUrl).toHaveBeenCalledWith("backend-prod", "dev-id-token"))
    expect(screen.getByTitle("Resource graph for Production state")).toHaveAttribute("src", "https://example.com/graph.png")

    fireEvent.click(screen.getByRole("button", { name: "State History" }))
    expect(screen.getByText("s3://tf-prod-state/env/prod/terraform.tfstate")).toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: "Autoscan" }))
    expect(screen.getByText("Autoscan History")).toBeInTheDocument()
    fireEvent.click(screen.getByRole("button", { name: /Run Autoscan/i }))
    await waitFor(() => expect(resourceMocks.saveDriftGuard).toHaveBeenCalledWith(
      expect.objectContaining({
        backendId: "backend-prod",
        email: "dev@gmail.com",
        repository: "png261/hcp-terraform",
      }),
      "dev-id-token"
    ))
    expect(resourceMocks.runDriftGuard).toHaveBeenCalledWith("guard-prod", "dev-id-token")

    fireEvent.click(screen.getByRole("button", { name: "Drift Alert" }))
    expect(screen.getByText("prod-logs")).toBeInTheDocument()
    expect(screen.getByText("aws_s3_bucket.logs")).toBeInTheDocument()
    expect(screen.getByText("app-server")).toBeInTheDocument()
    fireEvent.click(screen.getByRole("button", { name: /prod-logs/i }))
    const driftIssueDialog = screen.getByRole("dialog", { name: /prod-logs/i })
    expect(within(driftIssueDialog).getByText("Issue Context")).toBeInTheDocument()
    expect(within(driftIssueDialog).getByText("State Backend")).toBeInTheDocument()
    expect(within(driftIssueDialog).getByText("Drift Detail")).toBeInTheDocument()
    expect(within(driftIssueDialog).getByText("Drift Visualization")).toBeInTheDocument()
    expect(within(driftIssueDialog).getByText("Attribute")).toBeInTheDocument()
    expect(within(driftIssueDialog).getByText("Expected (Terraform)")).toBeInTheDocument()
    expect(within(driftIssueDialog).getByText("Actual (AWS)")).toBeInTheDocument()
    expect(within(driftIssueDialog).getAllByText("Not returned by Cloudrift").length).toBeGreaterThan(0)
    expect(within(driftIssueDialog).getByText("tags.CloudriftDrift")).toBeInTheDocument()
    expect(within(driftIssueDialog).queryByText("<planned>")).not.toBeInTheDocument()
    expect(within(driftIssueDialog).queryByText("<actual>")).not.toBeInTheDocument()
    fireEvent.click(within(driftIssueDialog).getAllByRole("button", { name: "Close" })[0])
    fireEvent.click(screen.getAllByRole("button", { name: /Fix error/i })[0])
    expect(storeActions.requestRepositoryChat).toHaveBeenCalledWith(
      repository,
      expect.stringContaining("State backend: s3://tf-prod-state/env/prod/terraform.tfstate"),
      expect.objectContaining({
        backendId: "backend-prod",
        repository,
      })
    )
    const alertFixPrompt = storeActions.requestRepositoryChat.mock.calls.at(-1)?.[1] as string
    expect(alertFixPrompt).toContain("Fix only this issue context:")
    expect(alertFixPrompt).toContain("Alert 1:")
    expect(alertFixPrompt).toContain("Issue type: drift")
    expect(alertFixPrompt).toContain("Kind: drift")
    expect(alertFixPrompt).toContain("Drift detail:")
    expect(alertFixPrompt).toContain("Resource type: aws_s3_bucket")
    expect(alertFixPrompt).toContain("Extra actual/current attributes:")
    expect(alertFixPrompt).toContain("tags.CloudriftDrift: manual-console-change-20260510")
    expect(alertFixPrompt).toContain("Attribute diffs:")
    expect(alertFixPrompt).toContain("Attribute | Expected (Terraform) | Actual (AWS)")
    expect(alertFixPrompt).toContain("acl:")
    expect(alertFixPrompt).toContain("Cloudrift reported this attribute changed but did not return concrete expected or actual values.")
    expect(alertFixPrompt).not.toContain("<planned>")
    expect(alertFixPrompt).not.toContain("<actual>")
    expect(alertFixPrompt).not.toContain("Kind: policy")
    expect(alertFixPrompt).not.toContain("S3 encryption required")
    expect(alertFixPrompt).not.toContain("```json")
    expect(alertFixPrompt).not.toContain("rawResult")
    fireEvent.click(screen.getByRole("button", { name: "Policy Alert" }))
    expect(screen.getByText("S3 encryption required")).toBeInTheDocument()
    fireEvent.click(screen.getByRole("button", { name: /S3 encryption required/i }))
    const policyIssueDialog = screen.getByRole("dialog", { name: /S3 encryption required/i })
    expect(within(policyIssueDialog).getByText("Issue Context")).toBeInTheDocument()
    expect(within(policyIssueDialog).getByText("State Backend")).toBeInTheDocument()
    expect(within(policyIssueDialog).getByText("Policy Detail")).toBeInTheDocument()
    expect(within(policyIssueDialog).getByText("Policy ID")).toBeInTheDocument()
    expect(within(policyIssueDialog).getByText("Policy name")).toBeInTheDocument()
    expect(within(policyIssueDialog).getAllByText("Default encryption is missing").length).toBeGreaterThan(0)
    fireEvent.click(within(policyIssueDialog).getAllByRole("button", { name: "Close" })[0])
    expect(screen.getAllByRole("link", { name: /View pull request/i })[0]).toHaveAttribute(
      "href",
      "https://github.com/png261/hcp-terraform/pull/42"
    )
    fireEvent.click(screen.getByRole("button", { name: "Scan History" }))
    expect(screen.getByText("scan-prod")).toBeInTheDocument()
  })

  it("manages state backends from settings", async () => {
    const confirm = vi.spyOn(window, "confirm").mockReturnValue(true)
    renderWithRouter(<SettingsPage />, ["/settings"])

    expect(await screen.findByRole("heading", { name: "Settings" })).toBeInTheDocument()
    fireEvent.click(screen.getByRole("tab", { name: /State Backend/i }))
    expect(await screen.findByText("Production state")).toBeInTheDocument()
    fireEvent.click(screen.getByRole("button", { name: /Add State Backend/i }))
    const dialog = await screen.findByRole("dialog")
    fireEvent.change(within(dialog).getByLabelText("Name"), {
      target: { value: "New production state" },
    })
    fireEvent.change(within(dialog).getByLabelText("State key"), {
      target: { value: "env/new/terraform.tfstate" },
    })
    fireEvent.click(within(dialog).getByRole("button", { name: /Browse buckets/i }))
    expect(await within(dialog).findByText("tf-new-state")).toBeInTheDocument()
    fireEvent.click(within(dialog).getByText("tf-new-state"))
    fireEvent.click(within(dialog).getByRole("button", { name: /^Add State Backend$/i }))

    await waitFor(() => expect(resourceMocks.createStateBackend).toHaveBeenCalledWith(
      expect.objectContaining({
        name: "New production state",
        bucket: "tf-new-state",
        key: "env/new/terraform.tfstate",
        credentialId: "cred-1",
        repository,
      }),
      "dev-id-token"
    ))
    expect(await screen.findByText("State backend added and resource graph generated")).toBeInTheDocument()

    const productionRow = screen.getByText("Production state").closest("tr")
    if (!productionRow) throw new Error("Production state row was not found")
    fireEvent.click(within(productionRow).getByRole("button", { name: "Remove" }))
    await waitFor(() => expect(resourceMocks.deleteStateBackend).toHaveBeenCalledWith("backend-prod", "dev-id-token"))
    expect(confirm).toHaveBeenCalled()
    confirm.mockRestore()
  })

  it("keeps resource catalog data in the Zustand cache until the user reloads", async () => {
    const firstRender = renderWithRouter(<ResourceCatalogPage />, ["/resource-catalog"])

    expect(await screen.findByText("prod-logs")).toBeInTheDocument()
    await waitFor(() => expect(resourceMocks.listStateBackends).toHaveBeenCalledTimes(1))
    firstRender.unmount()

    renderWithRouter(<ResourceCatalogPage />, ["/resource-catalog"])

    expect(await screen.findByText("prod-logs")).toBeInTheDocument()
    expect(resourceMocks.listStateBackends).toHaveBeenCalledTimes(1)

    fireEvent.click(screen.getByRole("button", { name: /Reload/i }))
    await waitFor(() => expect(resourceMocks.listStateBackends).toHaveBeenCalledTimes(2))
    expect(storeActions.loadResourceCatalog).toHaveBeenLastCalledWith("dev-id-token", { force: true })
  })

  it("covers pull request summaries, filtering, external links, and chat handoff", async () => {
    renderWithRouter(<PullRequestsPage />, ["/pull-requests"])

    expect(await screen.findByRole("heading", { name: "Pull Requests" })).toBeInTheDocument()
    await waitFor(() =>
      expect(storeActions.loadPullRequests).toHaveBeenCalledWith(
        "png261/hcp-terraform",
        "all",
        "dev-id-token",
        { force: false }
      )
    )
    expect(screen.getByText("#42 Fix Terraform drift")).toBeInTheDocument()
    expect(screen.getByText("#41 Old closed change")).toBeInTheDocument()
    expect(screen.getByText("2 of 2 pull requests")).toBeInTheDocument()
    expect(screen.getByText("3 reactions")).toBeInTheDocument()

    fireEvent.change(screen.getByLabelText("State"), { target: { value: "open" } })
    expect(screen.getByText("#42 Fix Terraform drift")).toBeInTheDocument()
    expect(screen.queryByText("#41 Old closed change")).not.toBeInTheDocument()
    expect(screen.getByText("1 of 2 pull requests")).toBeInTheDocument()

    expect(screen.getByRole("link", { name: /View PR/i })).toHaveAttribute(
      "href",
      "https://github.com/png261/hcp-terraform/pull/42"
    )
    fireEvent.click(screen.getByRole("button", { name: /View chat/i }))
    expect(storeActions.setActiveSessionId).toHaveBeenCalledWith("session-pr-42")

    await waitFor(() => expect(screen.getByRole("button", { name: /Reload/i })).toBeEnabled())
  })
})
