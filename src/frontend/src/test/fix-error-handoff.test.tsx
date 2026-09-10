import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { MemoryRouter } from "react-router-dom"
import { beforeEach, describe, expect, it, vi } from "vitest"

const repository = vi.hoisted(() => ({
  owner: "png261",
  name: "hcp-terraform",
  fullName: "png261/hcp-terraform",
  defaultBranch: "main",
}))

const resourceMocks = vi.hoisted(() => ({
  listAwsCredentials: vi.fn(),
  listChatSessions: vi.fn(),
  listDriftGuards: vi.fn(),
  listGitHubPullRequests: vi.fn(),
  listResourceScans: vi.fn(),
  listStateBackendResources: vi.fn(),
  listStateBackends: vi.fn(),
  saveChatSessions: vi.fn(),
}))

const agentCoreClientMock = vi.hoisted(() => ({
  githubAction: vi.fn(async (action: string) =>
    action === "listInstalledRepositories"
      ? { repositories: [repository] }
      : { status: "ok" }
  ),
  cancelSession: vi.fn(async () => undefined),
  invoke: vi.fn(async () => undefined),
}))

const storage = vi.hoisted(() => {
  let items: Record<string, string> = {}
  return {
    getItem: vi.fn((key: string) => items[key] ?? null),
    setItem: vi.fn((key: string, value: string) => {
      items[key] = value
    }),
    removeItem: vi.fn((key: string) => {
      delete items[key]
    }),
    clear: vi.fn(() => {
      items = {}
    }),
  }
})

vi.stubGlobal("localStorage", storage)

vi.mock("@/hooks/useAuth", () => ({
  useAuth: () => ({
    isAuthenticated: true,
    user: {
      access_token: "access-token",
      id_token: "id-token",
      profile: { email: "dev@gmail.com", sub: "dev-user" },
    },
    signIn: vi.fn(),
    signOut: vi.fn(),
    isLoading: false,
    error: null,
    token: "id-token",
  }),
}))

vi.mock("@/hooks/useInstalledRepositories", () => ({
  useInstalledRepositories: () => ({
    repositories: [repository],
    isLoading: false,
    error: null,
    reload: vi.fn(),
  }),
}))

vi.mock("@/hooks/useToolRenderer", () => ({
  getToolRenderer: vi.fn(() => null),
  useDefaultTool: vi.fn(),
}))

vi.mock("@/components/files/FileSystemPanel", () => ({
  FileSystemPanel: () => <div data-testid="filesystem-panel" />,
}))

vi.mock("@/components/ui/cursor-driven-particle-typography", () => ({
  CursorDrivenParticleTypography: ({ text }: { text: string }) => <div>{text}</div>,
}))

vi.mock("@/lib/agentcore-client", () => ({
  AgentCoreClient: vi.fn().mockImplementation(function AgentCoreClient() {
    return {
      githubAction: agentCoreClientMock.githubAction,
      cancelSession: agentCoreClientMock.cancelSession,
      invoke: agentCoreClientMock.invoke,
    }
  }),
}))

vi.mock("@/services/resourcesService", async importOriginal => {
  const actual = await importOriginal<typeof import("@/services/resourcesService")>()
  return {
    ...actual,
    deleteChatSession: vi.fn(),
    getUserConfig: vi.fn(),
    listAwsCredentials: resourceMocks.listAwsCredentials,
    listChatSessions: resourceMocks.listChatSessions,
    listDriftGuards: resourceMocks.listDriftGuards,
    listGitHubPullRequests: resourceMocks.listGitHubPullRequests,
    listResourceScans: resourceMocks.listResourceScans,
    listStateBackendResources: resourceMocks.listStateBackendResources,
    listStateBackends: resourceMocks.listStateBackends,
    saveChatSessions: resourceMocks.saveChatSessions,
    saveUserConfig: vi.fn(),
  }
})

const { default: AppRoutes } = await import("@/routes")
const { useWebAppStore } = await import("@/stores/webAppStore")

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
  policyAlerts: [],
  currentResources: [],
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
    address: "aws_instance.app",
    type: "aws_instance",
    name: "app",
    values: {
      id: "i-0123456789abcdef0",
      tags: { Name: "app-server" },
    },
    updatedAt: "2026-05-17T01:00:00.000Z",
  },
]

describe("Resource Catalog Fix error handoff", () => {
  beforeEach(() => {
    vi.clearAllMocks()
    Element.prototype.scrollIntoView = vi.fn()
    vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue({
      setTransform: vi.fn(),
      scale: vi.fn(),
      clearRect: vi.fn(),
      fillText: vi.fn(),
      measureText: vi.fn(() => ({ width: 320 })),
      getImageData: vi.fn(() => ({ width: 0, height: 0, data: new Uint8ClampedArray() })),
      beginPath: vi.fn(),
      arc: vi.fn(),
      fill: vi.fn(),
    } as unknown as CanvasRenderingContext2D)
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          agentRuntimeArn: "arn:aws:bedrock-agentcore:ap-southeast-1:123456789012:runtime/test",
          awsRegion: "ap-southeast-1",
        }),
      })
    )
    resourceMocks.listChatSessions.mockResolvedValue({ sessions: [], activeSessionId: "" })
    resourceMocks.saveChatSessions.mockImplementation(async payload => payload)
    resourceMocks.listStateBackends.mockResolvedValue([backend])
    resourceMocks.listStateBackendResources.mockResolvedValue(stateResources)
    resourceMocks.listResourceScans.mockResolvedValue([scan])
    resourceMocks.listDriftGuards.mockResolvedValue([])
    resourceMocks.listAwsCredentials.mockResolvedValue({ activeCredentialId: "cred-1", credentials: [] })
    resourceMocks.listGitHubPullRequests.mockResolvedValue([])
    useWebAppStore.setState({
      sessions: [
        {
          id: "session-existing",
          name: "Existing chat",
          history: [],
          startDate: "2026-05-17T01:00:00.000Z",
          endDate: "2026-05-17T01:00:00.000Z",
          repository: null,
          stateBackend: null,
          pullRequest: null,
        },
      ],
      activeSessionId: "session-existing",
      repositoryChatRequest: null,
      chatSessionsLoadedFor: "id-token",
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
  })

  it("creates a new chat with repository, state backend, and fix prompt without blanking the page", async () => {
    render(
      <MemoryRouter initialEntries={["/resource-catalog"]}>
        <AppRoutes />
      </MemoryRouter>
    )

    expect(await screen.findByRole("heading", { name: "Resource Catalog" })).toBeInTheDocument()
    expect(await screen.findByText("app-server")).toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: /Fix drift/i }))

    const handoffState = useWebAppStore.getState()
    expect(handoffState.activeSessionId).toBe(handoffState.repositoryChatRequest?.sessionId)
    expect(handoffState.sessions[0]).toMatchObject({
      id: handoffState.repositoryChatRequest?.sessionId,
      name: "Fix Terraform issue",
      repository,
      stateBackend: expect.objectContaining({
        backendId: "backend-prod",
        bucket: "tf-prod-state",
        key: "env/prod/terraform.tfstate",
      }),
      history: [],
    })

    await waitFor(() =>
      expect(agentCoreClientMock.githubAction).toHaveBeenCalledWith(
        "setupRepositoryWorkspace",
        expect.not.stringMatching(/^session-existing$/),
        "access-token",
        repository
      )
    )
    await waitFor(() =>
      expect(agentCoreClientMock.invoke).toHaveBeenCalledWith(
        expect.stringContaining("aws_instance.app"),
        expect.not.stringMatching(/^session-existing$/),
        "access-token",
        expect.any(Function),
        repository,
        [],
        expect.objectContaining({
          backendId: "backend-prod",
          bucket: "tf-prod-state",
          key: "env/prod/terraform.tfstate",
          repository,
        }),
        expect.any(AbortSignal)
      )
    )
    const prompt = agentCoreClientMock.invoke.mock.calls[0][0] as string
    expect(prompt).toContain("Fix only this issue context:")
    expect(prompt).toContain("Resource address: aws_instance.app")
    expect(prompt).toContain("Issue type: drift")
    expect(prompt).toContain("Kind: drift")
    expect(prompt).toContain("Alert 1:")
    expect(prompt).toContain("Drift detail:")
    expect(prompt).toContain("Resource type: aws_instance")
    expect(prompt).toContain("Resource ID: i-0123456789abcdef0")
    expect(prompt).toContain("Attribute diffs:")
    expect(prompt).toContain("Attribute | Expected (Terraform) | Actual (AWS)")
    expect(prompt).toContain("Expected (Terraform): t3.micro")
    expect(prompt).toContain("Actual (AWS): t3.small")
    expect(prompt).toContain("Actual/current attributes:")
    expect(prompt).toContain("Change needed:")
    expect(prompt).not.toContain("Kind: policy")
    expect(prompt).not.toContain("```json")
    expect(prompt).not.toContain("rawResult")
    expect(screen.getByRole("form", { name: "chat input" })).toBeInTheDocument()
    expect(screen.queryByText("Something went wrong")).not.toBeInTheDocument()
  })
})
