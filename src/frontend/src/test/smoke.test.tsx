import { fireEvent, render, screen, waitFor, within } from "@testing-library/react"
import type { ReactElement } from "react"
import { MemoryRouter } from "react-router-dom"
import { readFileSync } from "fs"
import { resolve } from "path"
import { beforeEach, describe, expect, it, vi } from "vitest"
import { ChatInput, NO_REPOSITORY_VALUE } from "@/components/chat/ChatInput"
import { AppSidebar } from "@/components/layout/AppSidebar"
import ResourceCatalogPage from "@/routes/ResourceCatalogPage"
import PullRequestsPage from "@/routes/PullRequestsPage"
import SettingsPage from "@/routes/SettingsPage"
import AppRoutes from "@/routes"
import { useWebAppStore } from "@/stores/webAppStore"

const mockRepository = vi.hoisted(() => ({
  owner: "png261",
  name: "hcp-terraform",
  fullName: "png261/hcp-terraform",
  defaultBranch: "main",
}))

const repository = mockRepository

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
  persistChatSessions: vi.fn(async () => ({ sessions: [], activeSessionId: "" })),
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
  listS3Buckets: vi.fn(),
  createStateBackend: vi.fn(),
  deleteStateBackend: vi.fn(),
  getStateBackendGraphUrl: vi.fn(),
  saveDriftGuard: vi.fn(),
  runDriftGuard: vi.fn(),
  saveAwsCredential: vi.fn(),
  deleteAwsCredential: vi.fn(),
}))

const agentCoreClientMock = vi.hoisted(() => ({
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
}))

vi.mock("@/hooks/useAuth", () => ({
  useAuth: () => authState,
}))

vi.mock("@/components/chat/ChatInterface", () => ({
  default: () => <div data-testid="chat-interface">Chat smoke surface</div>,
}))

vi.mock("@/hooks/useInstalledRepositories", () => ({
  useInstalledRepositories: () => ({
    repositories: [mockRepository],
    isLoading: false,
    error: null,
  }),
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
    <select aria-label="GitHub Repository" value={value} onChange={event => onValueChange(event.target.value)}>
      {repositories.map(item => (
        <option key={item.fullName} value={item.fullName}>
          {item.fullName}
        </option>
      ))}
    </select>
  ),
}))

vi.mock("@/lib/agentcore-client", () => ({
  AgentCoreClient: vi.fn().mockImplementation(function AgentCoreClient() {
    return {
      githubAction: agentCoreClientMock.githubAction,
    }
  }),
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
  const emptyCatalog = () => ({
    backends: [],
    stateResources: [],
    scans: [],
    guards: [],
    credentials: [],
  })
  const useWebAppStore = create<MockState>((set, get) => ({
    sessions: [
      {
        id: "session-1",
        name: "Dev chat",
        history: [
          {
            role: "user",
            content: "Create a smoke test",
            timestamp: "2026-05-17T01:00:00.000Z",
          },
          {
            role: "assistant",
            content: "Done",
            timestamp: "2026-05-17T01:00:01.000Z",
          },
        ],
        startDate: "2026-05-17T01:00:00.000Z",
        endDate: "2026-05-17T01:00:01.000Z",
        repository: null,
        pullRequest: null,
      },
      {
        id: "session-pr-42",
        name: "Fix drift",
        history: [
          {
            role: "user",
            content: "Fix policy compliance issue.",
            timestamp: "2026-05-17T01:20:00.000Z",
          },
        ],
        startDate: "2026-05-17T01:20:00.000Z",
        endDate: "2026-05-17T01:25:00.000Z",
        repository: mockRepository,
        pullRequest: {
          number: 42,
          url: "https://github.com/png261/hcp-terraform/pull/42",
        },
      },
    ],
    activeSessionId: "session-1",
    selectedRepository: mockRepository,
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
    persistChatSessions: storeActions.persistChatSessions,
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
      if (!options.force && state.resourceCatalogLoadedFor === idToken) return state.resourceCatalog
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

vi.mock("@/services/resourcesService", async importOriginal => {
  const actual = await importOriginal<typeof import("@/services/resourcesService")>()
  return {
    ...actual,
    listStateBackends: resourceMocks.listStateBackends,
    listStateBackendResources: resourceMocks.listStateBackendResources,
    listResourceScans: resourceMocks.listResourceScans,
    listDriftGuards: resourceMocks.listDriftGuards,
    listAwsCredentials: resourceMocks.listAwsCredentials,
    listS3Buckets: resourceMocks.listS3Buckets,
    createStateBackend: resourceMocks.createStateBackend,
    deleteStateBackend: resourceMocks.deleteStateBackend,
    getStateBackendGraphUrl: resourceMocks.getStateBackendGraphUrl,
    saveDriftGuard: resourceMocks.saveDriftGuard,
    runDriftGuard: resourceMocks.runDriftGuard,
    saveAwsCredential: resourceMocks.saveAwsCredential,
    deleteAwsCredential: resourceMocks.deleteAwsCredential,
  }
})

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
  graphGeneratedAt: "2026-05-17T01:00:00.000Z",
  graphResourceCount: 2,
  createdAt: "2026-05-17T01:00:00.000Z",
  updatedAt: "2026-05-17T01:00:00.000Z",
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
  startedAt: "2026-05-17T01:05:00.000Z",
  updatedAt: "2026-05-17T01:06:00.000Z",
  driftAlerts: [
    {
      resource_address: "aws_instance.app",
      resource_name: "app-server",
      severity: "medium",
      message: "Instance shape drifted",
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
    updatedAt: "2026-05-17T01:00:00.000Z",
  },
]

function renderWithRouter(ui: ReactElement, initialEntries = ["/"]) {
  return render(<MemoryRouter initialEntries={initialEntries}>{ui}</MemoryRouter>)
}

describe("project smoke coverage", () => {
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
      selectedRepository: repository,
      activeSessionId: "session-1",
      pullRequestsByKey: {},
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
    resourceMocks.listStateBackendResources.mockResolvedValue(stateResources)
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
        createdAt: "2026-05-17T01:00:00.000Z",
        updatedAt: "2026-05-17T01:06:00.000Z",
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
          accessKeyIdSuffix: "ABCD",
          region: "ap-southeast-1",
        },
      ],
    })
    resourceMocks.getStateBackendGraphUrl.mockResolvedValue({
      url: "https://example.com/graph.png",
      expiresIn: 300,
    })
    resourceMocks.listS3Buckets.mockResolvedValue([
      {
        name: "tf-prod-state",
        createdAt: "2026-05-17T01:00:00.000Z",
      },
    ])
    resourceMocks.createStateBackend.mockResolvedValue({
      ...backend,
      backendId: "backend-new",
      name: "New production state",
      key: "env/new/terraform.tfstate",
      graphKey: "backend-new.png",
    })
    resourceMocks.deleteStateBackend.mockResolvedValue({
      backendId: "backend-prod",
      deletedScans: 1,
      deletedDriftGuards: 1,
      deletedTerraformJobs: 0,
    })
    resourceMocks.saveDriftGuard.mockResolvedValue({
      guardId: "guard-prod",
      name: "Autoscan - Production state",
      backendId: "backend-prod",
      repository: "png261/hcp-terraform",
      frequency: "manual",
      email: "dev@gmail.com",
      enabled: true,
    })
    resourceMocks.runDriftGuard.mockResolvedValue({
      scan: {
        ...scan,
        scanId: "scan-autoscan",
      },
    })
    resourceMocks.saveAwsCredential.mockResolvedValue({
      configured: true,
      credentialId: "cred-new",
      name: "AKIA...",
      accessKeyIdSuffix: "WXYZ",
      accountId: "123456789012",
      region: "ap-southeast-1",
    })
    resourceMocks.deleteAwsCredential.mockResolvedValue({
      credentialId: "cred-new",
      deletedBackends: [],
      deletedBackendCount: 0,
      activeCredentialId: "cred-1",
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
        createdAt: "2026-05-17T01:20:00.000Z",
        githubUpdatedAt: "2026-05-17T01:25:00.000Z",
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
        title: "Closed cleanup",
        state: "closed",
        url: "https://github.com/png261/hcp-terraform/pull/41",
        author: "dev",
        headBranch: "old/change",
        baseBranch: "main",
        checkConclusion: "failure",
        createdAt: "2026-05-16T01:20:00.000Z",
        closedAt: "2026-05-16T02:20:00.000Z",
        changedFiles: 2,
      },
    ])
  })

  it("smokes auth, navigation, and the chat route for the dev account", async () => {
    renderWithRouter(
      <div className="lg:flex">
        <AppSidebar />
        <AppRoutes />
      </div>
    )

    expect(await screen.findByTestId("chat-interface")).toHaveTextContent("Chat smoke surface")
    expect(screen.getByText("dev@gmail.com")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Resource Catalog" })).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Pull Requests" })).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Settings" })).toBeInTheDocument()
    expect(screen.queryByText(/Please sign in/i)).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: /^New Chat$/i }))
    expect(storeActions.requestNewChat).toHaveBeenCalled()
  })

  it("smokes the composer attachment and context controls", () => {
    const onRepositoryChange = vi.fn()
    const onAttachmentsChange = vi.fn()
    render(
      <ChatInput
        attachments={[
          {
            id: "image-1",
            name: "architecture.png",
            type: "image/png",
            size: 128,
            dataUrl: "data:image/png;base64,iVBORw0KGgo=",
          },
        ]}
        input=""
        setInput={vi.fn()}
        handleSubmit={vi.fn()}
        isLoading={false}
        repositories={[repository]}
        selectedRepositoryFullName={NO_REPOSITORY_VALUE}
        onRepositoryChange={onRepositoryChange}
        onAttachmentsChange={onAttachmentsChange}
      />
    )

    expect(screen.getByPlaceholderText("Type your message...")).toBeInTheDocument()
    expect(screen.getByAltText("architecture.png")).toHaveAttribute("src", "data:image/png;base64,iVBORw0KGgo=")
    expect(screen.queryByText("architecture.png")).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole("button", { name: "Add context" }))
    fireEvent.click(screen.getByRole("combobox", { name: "GitHub repository" }))
    fireEvent.click(screen.getByRole("option", { name: "png261/hcp-terraform" }))
    expect(onRepositoryChange).toHaveBeenCalledWith("png261/hcp-terraform")
  })

  it("smokes the resource catalog resources, graph, autoscan, alerts, and fix handoff", async () => {
    renderWithRouter(<ResourceCatalogPage />, ["/resource-catalog"])

    expect(await screen.findByRole("heading", { name: "Resource Catalog" })).toBeInTheDocument()
    expect(await screen.findByText("prod-logs")).toBeInTheDocument()
    expect(screen.getByText("aws_s3_bucket.logs")).toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: "Visualize" }))
    fireEvent.click(screen.getByRole("button", { name: /View graph/i }))
    await waitFor(() => expect(resourceMocks.getStateBackendGraphUrl).toHaveBeenCalledWith("backend-prod", "dev-id-token"))
    expect(screen.getByTitle("Resource graph for Production state")).toHaveAttribute("src", "https://example.com/graph.png")

    fireEvent.click(screen.getByRole("button", { name: "State History" }))
    expect(screen.getByText("s3://tf-prod-state/env/prod/terraform.tfstate")).toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: "Autoscan" }))
    fireEvent.click(screen.getByRole("button", { name: /Run Autoscan/i }))
    await waitFor(() => expect(resourceMocks.saveDriftGuard).toHaveBeenCalledWith(
      expect.objectContaining({ backendId: "backend-prod", email: "dev@gmail.com" }),
      "dev-id-token"
    ))
    expect(resourceMocks.runDriftGuard).toHaveBeenCalledWith("guard-prod", "dev-id-token")

    fireEvent.click(screen.getByRole("button", { name: "Drift Alert" }))
    expect(screen.getByText("app-server")).toBeInTheDocument()
    fireEvent.click(screen.getAllByRole("button", { name: /Fix error/i })[0])
    expect(storeActions.requestRepositoryChat).toHaveBeenCalledWith(
      repository,
      expect.stringContaining("aws_instance.app"),
      expect.objectContaining({
        backendId: "backend-prod",
        repository,
      })
    )

    fireEvent.click(screen.getByRole("button", { name: "Policy Alert" }))
    expect(screen.getByText("S3 encryption required")).toBeInTheDocument()
    fireEvent.click(screen.getByRole("button", { name: "Scan History" }))
    expect(screen.getByText("scan-prod")).toBeInTheDocument()
  })

  it("smokes pull request summaries, filters, links, and chat handoff", async () => {
    renderWithRouter(<PullRequestsPage />, ["/pull-requests"])

    expect(await screen.findByRole("heading", { name: "Pull Requests" })).toBeInTheDocument()
    expect(await screen.findByText("#42 Fix Terraform drift")).toBeInTheDocument()
    expect(screen.getByText("#41 Closed cleanup")).toBeInTheDocument()
    expect(screen.getByText("2 of 2 pull requests")).toBeInTheDocument()

    fireEvent.change(screen.getByLabelText("State"), { target: { value: "open" } })
    expect(screen.getByText("#42 Fix Terraform drift")).toBeInTheDocument()
    expect(screen.queryByText("#41 Closed cleanup")).not.toBeInTheDocument()
    expect(screen.getByRole("link", { name: /View PR/i })).toHaveAttribute(
      "href",
      "https://github.com/png261/hcp-terraform/pull/42"
    )
    fireEvent.click(screen.getByRole("button", { name: /View chat/i }))
    expect(storeActions.setActiveSessionId).toHaveBeenCalledWith("session-pr-42")
  })

  it("smokes settings credentials, state backend management, and GitHub app controls", async () => {
    const confirm = vi.spyOn(window, "confirm").mockReturnValue(true)
    renderWithRouter(<SettingsPage />, ["/settings"])

    expect(await screen.findByRole("heading", { name: "Settings" })).toBeInTheDocument()
    expect(screen.getByRole("tab", { name: /General/i })).toHaveAttribute("aria-selected", "true")
    expect(await screen.findByRole("link", { name: "Uninstall GitHub App" })).toHaveAttribute(
      "href",
      "https://github.com/settings/installations"
    )

    fireEvent.click(screen.getByRole("tab", { name: /Credentials/i }))
    expect(await screen.findByText("Dev AWS")).toBeInTheDocument()
    expect(screen.getByText("1 related state backend")).toBeInTheDocument()
    fireEvent.click(screen.getByRole("button", { name: /Add Credential/i }))
    const credentialDialog = await screen.findByRole("dialog", { name: /Add AWS Credential/i })
    fireEvent.change(within(credentialDialog).getByPlaceholderText("AKIA..."), { target: { value: "AKIADEVSMOKE" } })
    fireEvent.change(within(credentialDialog).getByPlaceholderText("Secret key"), { target: { value: "test-secret" } })
    fireEvent.click(within(credentialDialog).getByRole("button", { name: /Save Credential/i }))

    await waitFor(() => expect(resourceMocks.saveAwsCredential).toHaveBeenCalledWith(
      expect.objectContaining({
        accessKeyId: "AKIADEVSMOKE",
        secretAccessKey: "test-secret",
      }),
      "dev-id-token"
    ))
    expect(await screen.findByText("AWS credential saved")).toBeInTheDocument()
    fireEvent.click(screen.getAllByRole("button", { name: "Remove" })[0])
    await waitFor(() => expect(resourceMocks.deleteAwsCredential).toHaveBeenCalledWith("cred-new", "dev-id-token"))
    expect(await screen.findByText("AWS credential removed")).toBeInTheDocument()

    fireEvent.click(screen.getByRole("tab", { name: /State Backend/i }))
    expect(await screen.findByText("Production state")).toBeInTheDocument()
    fireEvent.click(screen.getByRole("button", { name: "Add State Backend" }))
    const dialog = await screen.findByRole("dialog")
    fireEvent.change(within(dialog).getByLabelText("Name"), { target: { value: "New production state" } })
    fireEvent.change(within(dialog).getByLabelText("State key"), { target: { value: "env/new/terraform.tfstate" } })
    fireEvent.change(within(dialog).getByLabelText("Bucket"), { target: { value: "tf-prod-state" } })
    fireEvent.click(within(dialog).getByRole("button", { name: "Add State Backend" }))
    await waitFor(() => expect(resourceMocks.createStateBackend).toHaveBeenCalledWith(
      expect.objectContaining({
        name: "New production state",
        bucket: "tf-prod-state",
        key: "env/new/terraform.tfstate",
        credentialId: "cred-1",
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

  it("smokes hosted Cognito auth configuration without a custom auth form", () => {
    const authProviderContent = readFileSync(resolve(__dirname, "../components/auth/AuthProvider.tsx"), "utf-8")
    expect(authProviderContent).toContain("signInWithRedirect")
    expect(authProviderContent).toContain("loginWith")
    expect(authProviderContent).toContain("oauth")
    expect(authProviderContent).toContain("Redirecting to sign in...")
    expect(authProviderContent).not.toContain("function AuthScreen")
    expect(authProviderContent).not.toContain("<form")
  })
})
