import * as cdk from "aws-cdk-lib"
import * as cognito from "aws-cdk-lib/aws-cognito"
import * as ec2 from "aws-cdk-lib/aws-ec2"
import * as iam from "aws-cdk-lib/aws-iam"
import * as ssm from "aws-cdk-lib/aws-ssm"
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager"
import * as dynamodb from "aws-cdk-lib/aws-dynamodb"
import * as apigateway from "aws-cdk-lib/aws-apigateway"
import * as codebuild from "aws-cdk-lib/aws-codebuild"
import * as logs from "aws-cdk-lib/aws-logs"
import * as s3 from "aws-cdk-lib/aws-s3"
import * as agentcore from "@aws-cdk/aws-bedrock-agentcore-alpha"
import * as bedrockagentcore from "aws-cdk-lib/aws-bedrockagentcore"
import * as lambda from "aws-cdk-lib/aws-lambda"
import * as ecr_assets from "aws-cdk-lib/aws-ecr-assets"
import * as cr from "aws-cdk-lib/custom-resources"
import { Construct } from "constructs"
import { AppConfig } from "./utils/config-manager"
import { AgentCoreRole } from "./utils/agentcore-role"
import * as path from "path"
import * as fs from "fs"

export interface BackendStackProps extends cdk.NestedStackProps {
  config: AppConfig
  userPoolId: string
  userPoolClientId: string
  userPoolDomain: cognito.UserPoolDomain
  frontendUrl: string
}

export class BackendStack extends cdk.NestedStack {
  public readonly userPoolId: string
  public readonly userPoolClientId: string
  public readonly userPoolDomain: cognito.UserPoolDomain
  public resourcesApiUrl: string
  public sharedBucketName?: string
  public fileEventsApiUrl?: string
  public fileEventsApiId?: string
  public runtimeArn: string
  public memoryArn: string
  public memoryId: string
  public githubAppInstallUrl?: string
  private agentName: cdk.CfnParameter
  private userPool: cognito.IUserPool
  private machineClient: cognito.UserPoolClient
  private machineClientSecret: secretsmanager.Secret
  private runtimeCredentialProvider: cdk.CustomResource
  private agentRuntime: agentcore.Runtime
  private agentCodeBucket?: s3.Bucket
  private runtimeVpcResources?: {
    vpc: ec2.IVpc
    subnets: ec2.ISubnet[]
    securityGroups: ec2.ISecurityGroup[]
    subnetIds: string[]
    securityGroupIds: string[]
  }

  constructor(scope: Construct, id: string, props: BackendStackProps) {
    super(scope, id, props)

    // Store the Cognito values
    this.userPoolId = props.userPoolId
    this.userPoolClientId = props.userPoolClientId
    this.userPoolDomain = props.userPoolDomain

    // Import the Cognito resources from the other stack
    this.userPool = cognito.UserPool.fromUserPoolId(
      this,
      "ImportedUserPoolForBackend",
      props.userPoolId
    )
    // then create the user pool client
    cognito.UserPoolClient.fromUserPoolClientId(
      this,
      "ImportedUserPoolClient",
      props.userPoolClientId
    )

    // Create Machine-to-Machine authentication components
    this.createMachineAuthentication(props.config)

    // DEPLOYMENT ORDER EXPLANATION:
    // 1. Cognito User Pool & Client (created in separate CognitoStack)
    // 2. Machine Client & Resource Server (created above for M2M auth)
    // 3. AgentCore Gateway (created next - uses machine client for auth)
    // 4. AgentCore Runtime (created last - independent of gateway)
    //
    // This order ensures that authentication components are available before
    // the gateway that depends on them, while keeping the runtime separate
    // since it doesn't directly depend on the gateway.

    // Create AgentCore Gateway (before Runtime)
    this.createAgentCoreGateway(props.config)

    // Create OpenAI API Key Credential Provider
    this.createOpenAICredentialProvider(props.config)
    this.createGitHubCredentialProvider(props.config)

    // Create AgentCore Runtime resources
    this.createAgentCoreRuntime(props.config)

    // Store runtime ARN in SSM for frontend stack
    this.createRuntimeSSMParameters(props.config)

    // Store Cognito configuration in SSM for testing and frontend
    this.createCognitoSSMParameters(props.config)

    const resourcesTable = this.createResourcesTable(props.config)
    const resourceGraphBucket = this.createResourceGraphBucket(props.config)
    const driftProject = this.createCloudriftCodeBuildProject(props.config, resourcesTable)
    this.createResourcesApi(props.config, props.frontendUrl, resourcesTable, driftProject, resourceGraphBucket)
  }

  private createAgentCoreRuntime(config: AppConfig): void {
    // Parameters
    this.agentName = new cdk.CfnParameter(this, "AgentName", {
      type: "String",
      default: "FASTAgent",
      description: "Name for the agent runtime",
    })

    const stack = cdk.Stack.of(this)
    const deploymentType = config.backend.deployment_type

    // Create the agent runtime artifact based on deployment type
    let agentRuntimeArtifact: agentcore.AgentRuntimeArtifact
    let zipPackagerResource: cdk.CustomResource | undefined
    let runtimeArtifactVersion: string = deploymentType

    if (deploymentType === "zip") {
      // ZIP DEPLOYMENT: Use Lambda to package and upload to S3 (no Docker required)
      const repoRoot = path.resolve(__dirname, "..", "..") // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal
      const agentDir = path.join(repoRoot, "agent") // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal

      // Create S3 bucket for agent code
      const agentCodeBucket = new s3.Bucket(this, "AgentCodeBucket", {
        removalPolicy: cdk.RemovalPolicy.DESTROY,
        autoDeleteObjects: true,
        versioned: true,
        blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      })
      this.agentCodeBucket = agentCodeBucket

      // Lambda to package agent code
      const packagerLambda = new lambda.Function(this, "ZipPackagerLambda", {
        runtime: lambda.Runtime.PYTHON_3_12,
        handler: "index.handler",
        code: lambda.Code.fromAsset(path.join(__dirname, "..", "lambdas", "zip-packager")), // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal
        timeout: cdk.Duration.minutes(10),
        memorySize: 1024,
        ephemeralStorageSize: cdk.Size.gibibytes(2),
      })

      agentCodeBucket.grantReadWrite(packagerLambda)

      // Read agent code files and encode as base64
      const agentCode: Record<string, string> = {}

      // Read agent .py files
      for (const file of fs.readdirSync(agentDir)) {
        if (file.endsWith(".py")) {
          const content = fs.readFileSync(path.join(agentDir, file)) // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal
          agentCode[file] = content.toString("base64")
        }
      }

      // Read shared modules using the same import layout as the Docker image.
      const sharedModules: Record<string, string> = {
        gateway: "gateway",
        tools: "agentcore_tools",
      }
      for (const [source, target] of Object.entries(sharedModules)) {
        const moduleDir = path.join(repoRoot, source) // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal
        if (fs.existsSync(moduleDir)) {
          this.readDirRecursive(moduleDir, target, agentCode)
        }
      }
      for (const module of ["agents", "utils"]) {
        const moduleDir = path.join(agentDir, module) // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal
        if (fs.existsSync(moduleDir)) {
          this.readDirRecursive(moduleDir, module, agentCode)
        }
      }

      // Read requirements
      const requirementsPath = path.join(agentDir, "requirements.txt") // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal
      const requirements = fs
        .readFileSync(requirementsPath, "utf-8")
        .split("\n")
        .map(line => line.trim())
        .filter(line => line && !line.startsWith("#"))

      // Create hash for change detection
      // We use this to trigger update when content changes
      const contentHash = this.hashContent(JSON.stringify({ requirements, agentCode }))
      runtimeArtifactVersion = contentHash
      const deploymentPackageKey = `deployment_package-${contentHash}.zip`

      // Custom Resource to trigger packaging
      const provider = new cr.Provider(this, "ZipPackagerProvider", {
        onEventHandler: packagerLambda,
      })

      zipPackagerResource = new cdk.CustomResource(this, "ZipPackager", {
        serviceToken: provider.serviceToken,
        properties: {
          BucketName: agentCodeBucket.bucketName,
          ObjectKey: deploymentPackageKey,
          Requirements: requirements,
          AgentCode: agentCode,
          ContentHash: contentHash,
        },
      })

      // Store bucket name in SSM for updates
      new ssm.StringParameter(this, "AgentCodeBucketNameParam", {
        parameterName: `/${config.stack_name_base}/agent-code-bucket`,
        stringValue: agentCodeBucket.bucketName,
        description: "S3 bucket for agent code deployment packages",
      })

      agentRuntimeArtifact = agentcore.AgentRuntimeArtifact.fromS3(
        {
          bucketName: agentCodeBucket.bucketName,
          objectKey: deploymentPackageKey,
        },
        agentcore.AgentCoreRuntime.PYTHON_3_12,
        ["opentelemetry-instrument", "main.py"]
      )
    } else {
      // DOCKER DEPLOYMENT: Use container-based deployment
      agentRuntimeArtifact = agentcore.AgentRuntimeArtifact.fromAsset(
        path.resolve(__dirname, "..", ".."), // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal
        {
          platform: ecr_assets.Platform.LINUX_ARM64,
          file: "agent/Dockerfile",
        }
      )
    }

    // Configure network mode based on config.yaml settings.
    // PUBLIC: Runtime is accessible over the public internet (default).
    // VPC: Runtime is deployed into a user-provided VPC for private network isolation.
    //      The user must ensure their VPC has the necessary VPC endpoints for AWS services.
    //      See docs/DEPLOYMENT.md for the full list of required VPC endpoints.
    const networkConfiguration = this.buildNetworkConfiguration(config)

    // Configure JWT authorizer with Cognito
    const authorizerConfiguration = agentcore.RuntimeAuthorizerConfiguration.usingJWT(
      `https://cognito-idp.${stack.region}.amazonaws.com/${this.userPoolId}/.well-known/openid-configuration`,
      [this.userPoolClientId]
    )

    // Create AgentCore execution role
    const agentRole = new AgentCoreRole(this, "AgentCoreRole")

    // Create memory resource with short-term memory (conversation history) as default
    // To enable long-term strategies (summaries, preferences, facts), see docs/MEMORY_INTEGRATION.md
    const memory = new cdk.CfnResource(this, "AgentMemory", {
      type: "AWS::BedrockAgentCore::Memory",
      properties: {
        Name: cdk.Names.uniqueResourceName(this, { maxLength: 48 }),
        EventExpiryDuration: 30,
        Description: `Short-term memory for ${config.stack_name_base} agent`,
        MemoryStrategies: [
          {
            // Extracts and stores factual information shared by the user across sessions.
            // Stored under /facts/{actorId} — retrieved on each turn to personalise responses.
            SemanticMemoryStrategy: {
              Name: "FactExtractor",
              Namespaces: ["/facts/{actorId}"],
            },
          },
        ],
        MemoryExecutionRoleArn: agentRole.roleArn,
        Tags: {
          Name: `${config.stack_name_base}_Memory`,
          ManagedBy: "CDK",
        },
      },
    })
    const memoryId = memory.getAtt("MemoryId").toString()
    const memoryArn = memory.getAtt("MemoryArn").toString()

    // Store the memory ARN for access from main stack
    this.memoryArn = memoryArn
    this.memoryId = memoryId

    // Add memory-specific permissions to agent role
    agentRole.addToPrincipalPolicy(
      new iam.PolicyStatement({
        sid: "MemoryResourceAccess",
        effect: iam.Effect.ALLOW,
        actions: [
          "bedrock-agentcore:CreateEvent",
          "bedrock-agentcore:GetEvent",
          "bedrock-agentcore:ListEvents",
          "bedrock-agentcore:RetrieveMemoryRecords", // Only needed for long-term strategies
        ],
        resources: [memoryArn],
      })
    )

    // Add SSM permissions for AgentCore Gateway URL lookup
    agentRole.addToPrincipalPolicy(
      new iam.PolicyStatement({
        sid: "SSMParameterAccess",
        effect: iam.Effect.ALLOW,
        actions: ["ssm:GetParameter", "ssm:GetParameters"],
        resources: [
          `arn:aws:ssm:${this.region}:${this.account}:parameter/${config.stack_name_base}/*`,
        ],
      })
    )

    // Add Code Interpreter permissions
    agentRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "CodeInterpreterAccess",
        effect: iam.Effect.ALLOW,
        actions: [
          "bedrock-agentcore:StartCodeInterpreterSession",
          "bedrock-agentcore:StopCodeInterpreterSession",
          "bedrock-agentcore:InvokeCodeInterpreter",
        ],
        resources: [`arn:aws:bedrock-agentcore:${this.region}:aws:code-interpreter/*`],
      })
    )

    // Add OAuth2 Credential Provider access for AgentCore Runtime
    // The @requires_access_token decorator performs a two-stage process:
    // 1. GetOauth2CredentialProvider - Looks up provider metadata (ARN, vendor config, grant types)
    // 2. GetResourceOauth2Token - Uses metadata to fetch the actual access token from Token Vault
    agentRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "OAuth2CredentialProviderAccess",
        effect: iam.Effect.ALLOW,
        actions: [
          "bedrock-agentcore:GetOauth2CredentialProvider",
          "bedrock-agentcore:GetResourceOauth2Token",
        ],
        resources: [
          `arn:aws:bedrock-agentcore:${this.region}:${this.account}:oauth2-credential-provider/*`,
          `arn:aws:bedrock-agentcore:${this.region}:${this.account}:token-vault/*`,
          `arn:aws:bedrock-agentcore:${this.region}:${this.account}:workload-identity-directory/*`,
        ],
      })
    )

    // Add API Key Credential Provider access for AgentCore Runtime
    // The @requires_api_key decorator performs a two-stage process:
    // 1. GetApiKeyCredentialProvider - Looks up provider metadata (ARN, api key, additional fields)
    // 2. GetResourceApiKey - Uses metadata to fetch the actual API key from Token Vault
    agentRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "ApiKeyCredentialProviderAccess",
        effect: iam.Effect.ALLOW,
        actions: [
          "bedrock-agentcore:GetApiKeyCredentialProvider",
          "bedrock-agentcore:GetResourceApiKey",
        ],
        resources: [
          `arn:aws:bedrock-agentcore:${this.region}:${this.account}:api-key-credential-provider/*`,
          `arn:aws:bedrock-agentcore:${this.region}:${this.account}:token-vault/*`,
          `arn:aws:bedrock-agentcore:${this.region}:${this.account}:workload-identity-directory/*`,
        ],
      })
    )

    // Add Secrets Manager access for OAuth2
    // AgentCore Runtime needs to read two secrets:
    // 1. Machine client secret (created by CDK)
    // 2. Token Vault OAuth2 secret (created by AgentCore Identity)
    agentRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "SecretsManagerOAuth2Access",
        effect: iam.Effect.ALLOW,
        actions: ["secretsmanager:GetSecretValue"],
        resources: [
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:/${config.stack_name_base}/machine_client_secret*`,
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:bedrock-agentcore-identity!default/oauth2/${config.stack_name_base}-runtime-gateway-auth*`,
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:bedrock-agentcore-identity!default/apikey/${config.stack_name_base}-openai-credentials*`,
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:bedrock-agentcore-identity!default/apikey/${config.backend.github?.credential_provider_name || `${config.stack_name_base}-github-app`}*`,
        ],
      })
    )

    // Environment variables for the runtime
    const envVars: { [key: string]: string } = {
      AWS_REGION: stack.region,
      AWS_DEFAULT_REGION: stack.region,
      MEMORY_ID: memoryId,
      STACK_NAME: config.stack_name_base,
      GATEWAY_CREDENTIAL_PROVIDER_NAME: `${config.stack_name_base}-runtime-gateway-auth`, // Used by @requires_access_token decorator to look up the correct provider
      OPENAI_CREDENTIAL_PROVIDER_NAME: `${config.stack_name_base}-openai-credentials`, // Used by @requires_api_key decorator to look up OpenAI credentials
      OPENAI_BASE_URL: config.backend.openai?.base_url || "https://api.openai.com/v1",
      OPENAI_MODEL_ID: config.backend.openai?.model_id || "gpt-4o",
      GITHUB_CREDENTIAL_PROVIDER_NAME:
        config.backend.github?.credential_provider_name || `${config.stack_name_base}-github-app`,
      GITHUB_APP_ID: config.backend.github?.app_id || "",
      GITHUB_APP_SLUG: config.backend.github?.app_slug || "",
      INFRACOST_API_KEY: config.backend.secrets.infracost_api_key || "",
      // Controls whether the agent activates long-term semantic memory retrieval.
      // The memory resource always includes the SemanticMemoryStrategy (no cost to define it),
      // but retrieval is only performed when this is "true". See config.yaml: use_long_term_memory.
      USE_LONG_TERM_MEMORY: config.backend.use_long_term_memory ? "true" : "false",
      // Retrieval tuning for long-term memory. Only used when USE_LONG_TERM_MEMORY is "true".
      // See config.yaml: ltm_top_k and ltm_relevance_score.
      LTM_TOP_K: String(config.backend.ltm_top_k),
      LTM_RELEVANCE_SCORE: String(config.backend.ltm_relevance_score),
      SHARED_FILES_MOUNT_PATH: "/tmp/agentcore-runtime-files",
      SHARED_FILES_FALLBACK_PATH: "/tmp/agentcore-runtime-files",
      BYPASS_TOOL_CONSENT: "true",
    }

    // Create the runtime using L2 construct
    // requestHeaderConfiguration allows the agent to read the Authorization header
    // from RequestContext.request_headers, which is needed to securely extract the
    // user ID from the validated JWT token (sub claim) instead of trusting the payload body.
    const runtimeConstructId = deploymentType === "docker" ? "RuntimeDocker" : "Runtime"
    const runtimeNameSuffix = deploymentType === "docker" ? "_docker" : ""

    this.agentRuntime = new agentcore.Runtime(this, runtimeConstructId, {
      runtimeName: `${config.stack_name_base.replace(/-/g, "_")}_${this.agentName.valueAsString}${runtimeNameSuffix}`,
      agentRuntimeArtifact: agentRuntimeArtifact,
      executionRole: agentRole,
      networkConfiguration: networkConfiguration,
      protocolConfiguration: agentcore.ProtocolType.HTTP,
      environmentVariables: envVars,
      authorizerConfiguration: authorizerConfiguration,
      requestHeaderConfiguration: {
        allowlistedHeaders: ["Authorization"],
      },
      description: `Strands single agent runtime for ${config.stack_name_base}`,
    })

    // Make sure that ZIP is uploaded before Runtime is created
    if (zipPackagerResource) {
      this.agentRuntime.node.addDependency(zipPackagerResource)
    }

    // Store the runtime ARN
    this.runtimeArn = this.agentRuntime.agentRuntimeArn

    // Outputs
    new cdk.CfnOutput(this, "AgentRuntimeId", {
      description: "ID of the created agent runtime",
      value: this.agentRuntime.agentRuntimeId,
    })

    new cdk.CfnOutput(this, "AgentRuntimeArn", {
      description: "ARN of the created agent runtime",
      value: this.agentRuntime.agentRuntimeArn,
      exportName: `${config.stack_name_base}-AgentRuntimeArn`,
    })

    new cdk.CfnOutput(this, "AgentRoleArn", {
      description: "ARN of the agent execution role",
      value: agentRole.roleArn,
    })

    // Memory ARN output
    new cdk.CfnOutput(this, "MemoryArn", {
      description: "ARN of the agent memory resource",
      value: memoryArn,
    })
  }

  private createRuntimeSSMParameters(config: AppConfig): void {
    // Store runtime ARN in SSM for frontend stack
    new ssm.StringParameter(this, "RuntimeArnParam", {
      parameterName: `/${config.stack_name_base}/runtime-arn`,
      stringValue: this.runtimeArn,
    })
  }

  private createCognitoSSMParameters(config: AppConfig): void {
    // Store Cognito configuration in SSM for testing and frontend access
    new ssm.StringParameter(this, "CognitoUserPoolIdParam", {
      parameterName: `/${config.stack_name_base}/cognito-user-pool-id`,
      stringValue: this.userPoolId,
      description: "Cognito User Pool ID",
    })

    new ssm.StringParameter(this, "CognitoUserPoolClientIdParam", {
      parameterName: `/${config.stack_name_base}/cognito-user-pool-client-id`,
      stringValue: this.userPoolClientId,
      description: "Cognito User Pool Client ID",
    })

    new ssm.StringParameter(this, "MachineClientIdParam", {
      parameterName: `/${config.stack_name_base}/machine_client_id`,
      stringValue: this.machineClient.userPoolClientId,
      description: "Machine Client ID for M2M authentication",
    })

    // Use the correct Cognito domain format from the passed domain
    new ssm.StringParameter(this, "CognitoDomainParam", {
      parameterName: `/${config.stack_name_base}/cognito_provider`,
      stringValue: `${this.userPoolDomain.domainName}.auth.${cdk.Aws.REGION}.amazoncognito.com`,
      description: "Cognito domain URL for token endpoint",
    })
  }

  private createResourcesTable(config: AppConfig): dynamodb.Table {
    const resourcesTable = new dynamodb.Table(this, "ResourcesTable", {
      tableName: `${config.stack_name_base}-resources`,
      partitionKey: {
        name: "pk",
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: "sk",
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      pointInTimeRecoverySpecification: {
        pointInTimeRecoveryEnabled: true,
      },
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
    })

    resourcesTable.addGlobalSecondaryIndex({
      indexName: "type-updatedAt-index",
      partitionKey: {
        name: "type",
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: "updatedAt",
        type: dynamodb.AttributeType.STRING,
      },
      projectionType: dynamodb.ProjectionType.ALL,
    })

    return resourcesTable
  }

  private createResourceGraphBucket(config: AppConfig): s3.Bucket {
    const bucketPrefix = config.stack_name_base
      .toLowerCase()
      .replace(/[^a-z0-9.-]/g, "-")
      .slice(0, 20)
      .replace(/[-.]+$/g, "")

    return new s3.Bucket(this, "ResourceGraphBucket", {
      bucketName: `${bucketPrefix}-graphs-${this.account}-${this.region}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          expiration: cdk.Duration.days(30),
        },
      ],
    })
  }

  private createCloudriftCodeBuildProject(
    config: AppConfig,
    resourcesTable: dynamodb.Table
  ): codebuild.Project {
    const cloudriftImage = codebuild.LinuxBuildImage.fromAsset(this, "CloudriftBuildImage", {
      directory: path.join(__dirname, "..", "codebuild", "cloudrift-image"),
      platform: ecr_assets.Platform.LINUX_AMD64,
    })
    const cloudriftLogGroup = logs.LogGroup.fromLogGroupName(
      this,
      "CloudriftDriftProjectLogGroup",
      `/aws/codebuild/${config.stack_name_base}-cloudrift-drift`
    )

    const project = new codebuild.Project(this, "CloudriftDriftProject", {
      projectName: `${config.stack_name_base}-cloudrift-drift`,
      description: "Runs Cloudrift drift scans for user configured S3 Terraform state backends.",
      logging: {
        cloudWatch: {
          enabled: true,
          logGroup: cloudriftLogGroup,
          prefix: "build",
        },
      },
      environment: {
        buildImage: cloudriftImage,
        computeType: codebuild.ComputeType.SMALL,
        privileged: false,
        environmentVariables: {
          RESOURCES_TABLE_NAME: {
            value: resourcesTable.tableName,
          },
        },
      },
      timeout: cdk.Duration.minutes(20),
      buildSpec: codebuild.BuildSpec.fromObject({
        version: "0.2",
        phases: {
          build: {
            commands: [
              `python /usr/local/bin/cloudrift_scan.py`
            ],
          },
        },
      }),
    })

    resourcesTable.grantReadWriteData(project)
    cloudriftLogGroup.grantWrite(project)
    project.addToRolePolicy(
      new iam.PolicyStatement({
        sid: "ReadUserAwsCredentialSecrets",
        effect: iam.Effect.ALLOW,
        actions: ["secretsmanager:GetSecretValue"],
        resources: [
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:/${config.stack_name_base}/user-aws-credentials/*`,
        ],
      })
    )
    project.addToRolePolicy(
      new iam.PolicyStatement({
        sid: "PublishDriftGuardAlerts",
        effect: iam.Effect.ALLOW,
        actions: ["sns:Publish"],
        resources: [`arn:aws:sns:${this.region}:${this.account}:${config.stack_name_base}-drift-guard-*`],
      })
    )

    return project
  }

  private createResourcesApi(
    config: AppConfig,
    frontendUrl: string,
    resourcesTable: dynamodb.Table,
    driftProject: codebuild.Project,
    resourceGraphBucket: s3.Bucket
  ): void {
    const resourcesLambdaName = `${config.stack_name_base}-resources`
    const resourcesLambdaArn = `arn:aws:lambda:${this.region}:${this.account}:function:${resourcesLambdaName}`
    const schedulerRoleName = `${config.stack_name_base}-drift-guard-scheduler`
    const schedulerRoleArn = `arn:aws:iam::${this.account}:role/${schedulerRoleName}`
    const driftGuardSchedulerRole = new iam.Role(this, "DriftGuardSchedulerRole", {
      roleName: schedulerRoleName,
      assumedBy: new iam.ServicePrincipal("scheduler.amazonaws.com"),
      description: "Allows EventBridge Scheduler to invoke the Resources Lambda for Drift Guard scans.",
    })
    driftGuardSchedulerRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "InvokeResourcesLambda",
        effect: iam.Effect.ALLOW,
        actions: ["lambda:InvokeFunction"],
        resources: [resourcesLambdaArn],
      })
    )

    const resourcesLambda = new lambda.DockerImageFunction(this, "ResourcesLambda", {
      functionName: resourcesLambdaName,
      architecture: lambda.Architecture.X86_64,
      code: lambda.DockerImageCode.fromImageAsset(path.join(__dirname, "..", "lambdas", "resources"), {
        platform: ecr_assets.Platform.LINUX_AMD64,
      }), // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal
      environment: {
        TABLE_NAME: resourcesTable.tableName,
        CODEBUILD_PROJECT_NAME: driftProject.projectName,
        STACK_NAME_BASE: config.stack_name_base,
        DRIFT_GUARD_SCHEDULER_ROLE_ARN: schedulerRoleArn,
        RESOURCES_LAMBDA_ARN: resourcesLambdaArn,
        GITHUB_APP_SECRET_NAME: `/${config.stack_name_base}/github_app`,
        MEMORY_ID: this.memoryId,
        RESOURCE_GRAPH_BUCKET: resourceGraphBucket.bucketName,
        AWS_ICONS_PATH: "/opt/aws-official-icons",
        CORS_ALLOWED_ORIGINS: `${frontendUrl},http://localhost:3000`,
      },
      timeout: cdk.Duration.minutes(3),
      logGroup: new logs.LogGroup(this, "ResourcesLambdaLogGroup", {
        logGroupName: `/aws/lambda/${config.stack_name_base}-resources`,
        retention: logs.RetentionDays.ONE_WEEK,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      }),
    })

    resourcesTable.grantReadWriteData(resourcesLambda)
    resourceGraphBucket.grantReadWrite(resourcesLambda)
    resourcesLambda.addToRolePolicy(
      new iam.PolicyStatement({
        sid: "DeleteAgentCoreMemoryEvents",
        effect: iam.Effect.ALLOW,
        actions: [
          "bedrock-agentcore:ListEvents",
          "bedrock-agentcore:DeleteEvent",
        ],
        resources: [this.memoryArn],
      })
    )
    resourcesLambda.addToRolePolicy(
      new iam.PolicyStatement({
        sid: "StartCloudriftBuild",
        effect: iam.Effect.ALLOW,
        actions: ["codebuild:BatchGetBuilds", "codebuild:StartBuild"],
        resources: [driftProject.projectArn],
      })
    )
    resourcesLambda.addToRolePolicy(
      new iam.PolicyStatement({
        sid: "ReadCloudriftBuildLogs",
        effect: iam.Effect.ALLOW,
        actions: ["logs:GetLogEvents"],
        resources: [
          `arn:aws:logs:${this.region}:${this.account}:log-group:/aws/codebuild/${config.stack_name_base}-cloudrift-drift:log-stream:*`,
        ],
      })
    )
    resourcesLambda.addToRolePolicy(
      new iam.PolicyStatement({
        sid: "ManageUserAwsCredentialSecrets",
        effect: iam.Effect.ALLOW,
        actions: [
          "secretsmanager:CreateSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret",
          "secretsmanager:TagResource",
        ],
        resources: [
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:/${config.stack_name_base}/user-aws-credentials/*`,
        ],
      })
    )
    resourcesLambda.addToRolePolicy(
      new iam.PolicyStatement({
        sid: "ManageDriftGuardSchedules",
        effect: iam.Effect.ALLOW,
        actions: [
          "scheduler:CreateSchedule",
          "scheduler:DeleteSchedule",
          "scheduler:GetSchedule",
          "scheduler:UpdateSchedule",
        ],
        resources: [
          `arn:aws:scheduler:${this.region}:${this.account}:schedule/default/${config.stack_name_base}-drift-guard-*`,
        ],
      })
    )
    resourcesLambda.addToRolePolicy(
      new iam.PolicyStatement({
        sid: "PassDriftGuardSchedulerRole",
        effect: iam.Effect.ALLOW,
        actions: ["iam:PassRole"],
        resources: [driftGuardSchedulerRole.roleArn],
      })
    )
    resourcesLambda.addToRolePolicy(
      new iam.PolicyStatement({
        sid: "ManageDriftGuardAlertTopics",
        effect: iam.Effect.ALLOW,
        actions: ["sns:CreateTopic", "sns:ListSubscriptionsByTopic", "sns:Publish", "sns:Subscribe"],
        resources: [`arn:aws:sns:${this.region}:${this.account}:${config.stack_name_base}-drift-guard-*`],
      })
    )
    resourcesLambda.addToRolePolicy(
      new iam.PolicyStatement({
        sid: "SendDemoHtmlEmail",
        effect: iam.Effect.ALLOW,
        actions: ["ses:GetIdentityVerificationAttributes", "ses:SendEmail"],
        resources: ["*"],
      })
    )
    resourcesLambda.addToRolePolicy(
      new iam.PolicyStatement({
        sid: "ReadGitHubAppSecretForWebhooks",
        effect: iam.Effect.ALLOW,
        actions: ["secretsmanager:GetSecretValue"],
        resources: [
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:/${config.stack_name_base}/github_app*`,
        ],
      })
    )

    const api = new apigateway.RestApi(this, "ResourcesApi", {
      restApiName: `${config.stack_name_base}-resources-api`,
      description: "API for AWS credentials, state backends, and Cloudrift scan results",
      defaultCorsPreflightOptions: {
        allowOrigins: [frontendUrl, "http://localhost:3000"],
        allowMethods: ["GET", "POST", "DELETE", "OPTIONS"],
        allowHeaders: ["Content-Type", "Authorization"],
      },
      deployOptions: {
        stageName: "prod",
        throttlingRateLimit: 50,
        throttlingBurstLimit: 100,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: false,
        metricsEnabled: true,
        accessLogDestination: new apigateway.LogGroupLogDestination(
          new logs.LogGroup(this, "ResourcesApiAccessLogGroup", {
            logGroupName: `/aws/apigateway/${config.stack_name_base}-resources-api-access`,
            retention: logs.RetentionDays.ONE_WEEK,
            removalPolicy: cdk.RemovalPolicy.DESTROY,
          })
        ),
        accessLogFormat: apigateway.AccessLogFormat.jsonWithStandardFields(),
        tracingEnabled: true,
      },
    })

    const authorizer = new apigateway.CognitoUserPoolsAuthorizer(this, "ResourcesApiAuthorizer", {
      cognitoUserPools: [this.userPool],
      identitySource: "method.request.header.Authorization",
      authorizerName: `${config.stack_name_base}-resources-authorizer`,
    })
    const integration = new apigateway.LambdaIntegration(resourcesLambda, {
      allowTestInvoke: false,
    })
    const methodOptions = {
      authorizer,
      authorizationType: apigateway.AuthorizationType.COGNITO,
    }

    const credentialResource = api.root.addResource("aws-credential")
    credentialResource.addMethod("GET", integration, methodOptions)
    credentialResource.addMethod("POST", integration, methodOptions)
    const credentialsResource = api.root.addResource("aws-credentials")
    credentialsResource.addMethod("GET", integration, methodOptions)
    credentialsResource.addMethod("POST", integration, methodOptions)
    const credentialByIdResource = credentialsResource.addResource("{credentialId}")
    credentialByIdResource.addMethod("DELETE", integration, methodOptions)

    const userResource = api.root.addResource("user")
    const userChatSessionsResource = userResource.addResource("chat-sessions")
    userChatSessionsResource.addMethod("GET", integration, methodOptions)
    userChatSessionsResource.addMethod("POST", integration, methodOptions)
    const userChatSessionResource = userChatSessionsResource.addResource("{sessionId}")
    userChatSessionResource.addMethod("DELETE", integration, methodOptions)
    const userConfigResource = userResource.addResource("config")
    userConfigResource.addMethod("GET", integration, methodOptions)
    userConfigResource.addMethod("POST", integration, methodOptions)

    const resourcesRoot = api.root.addResource("resources")
    const backendsResource = resourcesRoot.addResource("state-backends")
    backendsResource.addMethod("GET", integration, methodOptions)
    backendsResource.addMethod("POST", integration, methodOptions)
    const s3BucketsResource = resourcesRoot.addResource("s3-buckets")
    s3BucketsResource.addMethod("GET", integration, methodOptions)
    const terraformPlansResource = resourcesRoot.addResource("terraform-plans")
    terraformPlansResource.addMethod("GET", integration, methodOptions)
    terraformPlansResource.addMethod("POST", integration, methodOptions)
    const backendResource = backendsResource.addResource("{backendId}")
    backendResource.addMethod("DELETE", integration, methodOptions)
    const backendPlanResource = backendResource.addResource("plan")
    backendPlanResource.addMethod("POST", integration, methodOptions)
    const backendResourcesResource = backendResource.addResource("resources")
    backendResourcesResource.addMethod("GET", integration, methodOptions)
    const backendGraphResource = backendResource.addResource("graph")
    backendGraphResource.addMethod("GET", integration, methodOptions)

    const scansResource = resourcesRoot.addResource("scans")
    scansResource.addMethod("GET", integration, methodOptions)
    scansResource.addMethod("POST", integration, methodOptions)
    const driftGuardsResource = resourcesRoot.addResource("drift-guards")
    driftGuardsResource.addMethod("GET", integration, methodOptions)
    driftGuardsResource.addMethod("POST", integration, methodOptions)
    const driftGuardResource = driftGuardsResource.addResource("{guardId}")
    const driftGuardRunResource = driftGuardResource.addResource("run")
    driftGuardRunResource.addMethod("POST", integration, methodOptions)
    const demoResource = resourcesRoot.addResource("demo")
    const scheduledAutofixDemoResource = demoResource.addResource("scheduled-drift-policy-autofix")
    scheduledAutofixDemoResource.addMethod("POST", integration, methodOptions)
    const scanResource = scansResource.addResource("{scanId}")
    const scanLogsResource = scanResource.addResource("logs")
    scanLogsResource.addMethod("GET", integration, methodOptions)
    const scanGraphResource = scanResource.addResource("graph")
    scanGraphResource.addMethod("GET", integration, methodOptions)

    const githubResource = api.root.addResource("github")
    const githubWebhookResource = githubResource.addResource("webhook")
    githubWebhookResource.addMethod("POST", integration)
    const githubWebhookSecretResource = githubResource.addResource("webhook-secret")
    githubWebhookSecretResource.addMethod("GET", integration, methodOptions)
    githubWebhookSecretResource.addMethod("POST", integration, methodOptions)
    const githubPullRequestsResource = githubResource.addResource("pull-requests")
    githubPullRequestsResource.addMethod("GET", integration, methodOptions)

    this.resourcesApiUrl = api.url

    new ssm.StringParameter(this, "ResourcesApiUrlParam", {
      parameterName: `/${config.stack_name_base}/resources-api-url`,
      stringValue: api.url,
      description: "Resources API Gateway URL",
    })
  }

  private createAgentCoreGateway(config: AppConfig): void {
    // Create comprehensive IAM role for gateway
    const gatewayRole = new iam.Role(this, "GatewayRole", {
      assumedBy: new iam.ServicePrincipal("bedrock-agentcore.amazonaws.com"),
      description: "Role for AgentCore Gateway with comprehensive permissions",
    })

    // Bedrock permissions (region-agnostic)
    gatewayRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"],
        resources: [
          "arn:aws:bedrock:*::foundation-model/*",
          `arn:aws:bedrock:*:${this.account}:inference-profile/*`,
        ],
      })
    )

    // SSM parameter access
    gatewayRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ["ssm:GetParameter", "ssm:GetParameters"],
        resources: [
          `arn:aws:ssm:${this.region}:${this.account}:parameter/${config.stack_name_base}/*`,
        ],
      })
    )

    // Cognito permissions
    gatewayRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ["cognito-idp:DescribeUserPoolClient", "cognito-idp:InitiateAuth"],
        resources: [this.userPool.userPoolArn],
      })
    )

    // CloudWatch Logs
    gatewayRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        resources: [
          `arn:aws:logs:${this.region}:${this.account}:log-group:/aws/bedrock-agentcore/*`,
        ],
      })
    )

    // Cognito OAuth2 configuration for gateway
    const cognitoIssuer = `https://cognito-idp.${this.region}.amazonaws.com/${this.userPool.userPoolId}`
    const cognitoDiscoveryUrl = `${cognitoIssuer}/.well-known/openid-configuration`

    // Create OAuth2 Credential Provider for AgentCore Runtime to authenticate with AgentCore Gateway
    // Uses cr.Provider with explicit Lambda to avoid logging secrets in CloudWatch
    const providerName = `${config.stack_name_base}-runtime-gateway-auth`

    // Lambda to create/delete OAuth2 provider
    const oauth2ProviderLambda = new lambda.Function(this, "OAuth2ProviderLambda", {
      runtime: lambda.Runtime.PYTHON_3_13,
      handler: "index.handler",
      code: lambda.Code.fromAsset(path.join(__dirname, "..", "lambdas", "oauth2-provider")), // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal
      timeout: cdk.Duration.minutes(5),
      logGroup: new logs.LogGroup(this, "OAuth2ProviderLambdaLogGroup", {
        logGroupName: `/aws/lambda/${config.stack_name_base}-oauth2-provider`,
        retention: logs.RetentionDays.ONE_WEEK,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      }),
    })

    // Grant Lambda permissions to read machine client secret
    this.machineClientSecret.grantRead(oauth2ProviderLambda)

    // Grant Lambda permissions for Bedrock AgentCore operations
    // OAuth2 Credential Provider operations - scoped to all providers in default Token Vault
    // Note: Need both vault-level and nested resource permissions because:
    // - CreateOauth2CredentialProvider checks permission on vault itself (token-vault/default)
    // - Also checks permission on the nested resource path (token-vault/default/oauth2credentialprovider/*)
    oauth2ProviderLambda.addToRolePolicy(
      new iam.PolicyStatement({
        actions: [
          "bedrock-agentcore:CreateOauth2CredentialProvider",
          "bedrock-agentcore:DeleteOauth2CredentialProvider",
          "bedrock-agentcore:GetOauth2CredentialProvider",
        ],
        resources: [
          `arn:aws:bedrock-agentcore:${this.region}:${this.account}:token-vault/default`,
          `arn:aws:bedrock-agentcore:${this.region}:${this.account}:token-vault/default/oauth2credentialprovider/*`,
        ],
      })
    )

    // Token Vault operations - scoped to default vault
    // Note: Need both exact match (default) and wildcard (default/*) because:
    // - AWS checks permission on the vault container itself (token-vault/default)
    // - AWS also checks permission on resources inside (token-vault/default/*)
    oauth2ProviderLambda.addToRolePolicy(
      new iam.PolicyStatement({
        actions: [
          "bedrock-agentcore:CreateTokenVault",
          "bedrock-agentcore:GetTokenVault",
          "bedrock-agentcore:DeleteTokenVault",
        ],
        resources: [
          "*",
        ],
      })
    )

    // Grant Lambda permissions for Token Vault secret management
    // Scoped to OAuth2 secrets in AgentCore Identity default namespace
    oauth2ProviderLambda.addToRolePolicy(
      new iam.PolicyStatement({
        actions: [
          "secretsmanager:CreateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:PutSecretValue",
        ],
        resources: [
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:bedrock-agentcore-identity!default/oauth2/*`,
        ],
      })
    )

    // Create Custom Resource Provider
    const oauth2Provider = new cr.Provider(this, "OAuth2ProviderProvider", {
      onEventHandler: oauth2ProviderLambda,
    })

    // Create Custom Resource
    const runtimeCredentialProvider = new cdk.CustomResource(this, "RuntimeCredentialProvider", {
      serviceToken: oauth2Provider.serviceToken,
      properties: {
        ProviderName: providerName,
        ClientSecretArn: this.machineClientSecret.secretArn,
        DiscoveryUrl: cognitoDiscoveryUrl,
        ClientId: this.machineClient.userPoolClientId,
      },
    })

    // Store for use in createAgentCoreRuntime()
    this.runtimeCredentialProvider = runtimeCredentialProvider

    // Create Gateway using L1 construct (CfnGateway)
    // This replaces the Custom Resource approach with native CloudFormation support
    const gateway = new bedrockagentcore.CfnGateway(this, "AgentCoreGateway", {
      name: `${config.stack_name_base}-gateway`,
      roleArn: gatewayRole.roleArn,
      protocolType: "MCP",
      protocolConfiguration: {
        mcp: {
          supportedVersions: ["2025-03-26"],
          // Optional: Enable semantic search for tools
          // searchType: "SEMANTIC",
        },
      },
      authorizerType: "CUSTOM_JWT",
      authorizerConfiguration: {
        customJwtAuthorizer: {
          allowedClients: [this.machineClient.userPoolClientId],
          discoveryUrl: cognitoDiscoveryUrl,
        },
      },
      description: "AgentCore Gateway with MCP protocol and JWT authentication",
    })

    // Ensure proper creation order
    gateway.node.addDependency(this.machineClient)
    gateway.node.addDependency(gatewayRole)

    // Store AgentCore Gateway URL in SSM for AgentCore Runtime access
    new ssm.StringParameter(this, "GatewayUrlParam", {
      parameterName: `/${config.stack_name_base}/gateway_url`,
      stringValue: gateway.attrGatewayUrl,
      description: "AgentCore Gateway URL",
    })

    // Output gateway information
    new cdk.CfnOutput(this, "GatewayId", {
      value: gateway.attrGatewayIdentifier,
      description: "AgentCore Gateway ID",
    })

    new cdk.CfnOutput(this, "GatewayUrl", {
      value: gateway.attrGatewayUrl,
      description: "AgentCore Gateway URL",
    })

    new cdk.CfnOutput(this, "GatewayArn", {
      value: gateway.attrGatewayArn,
      description: "AgentCore Gateway ARN",
    })
  }

  private createOpenAICredentialProvider(config: AppConfig): void {
    const openaiApiKeySecret = new secretsmanager.Secret(
      this,
      "OpenAIApiKeySecret",
      {
        secretName: `/${config.stack_name_base}/openai_api_key`,
        secretStringValue: cdk.SecretValue.unsafePlainText(
          JSON.stringify({
            api_key: config.backend.secrets.openai_api_key,
            base_url: config.backend.openai?.base_url || "https://api.openai.com/v1",
            model_id: config.backend.openai?.model_id || "gpt-4o",
          })
        ),
        description: "OpenAI-compatible API credentials for AgentCore Identity",
      }
    )

    // Create Lambda for OpenAI Credential Provider management
    const openaiProviderLambda = new lambda.Function(this, "OpenAIProviderLambda", {
      runtime: lambda.Runtime.PYTHON_3_13,
      handler: "index.handler",
      code: lambda.Code.fromAsset(
        path.join(__dirname, "../lambdas/openai-credential-provider")
      ),
      timeout: cdk.Duration.seconds(30),
      logGroup: new logs.LogGroup(this, "OpenAIProviderLambdaLogGroup", {
        logGroupName: `/aws/lambda/${config.stack_name_base}-openai-provider`,
        retention: logs.RetentionDays.ONE_WEEK,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      }),
    })

    // Grant Lambda permissions for API Key Credential Provider
    openaiProviderLambda.addToRolePolicy(
      new iam.PolicyStatement({
        actions: [
          "bedrock-agentcore:CreateApiKeyCredentialProvider",
          "bedrock-agentcore:GetApiKeyCredentialProvider",
          "bedrock-agentcore:UpdateApiKeyCredentialProvider",
          "bedrock-agentcore:DeleteApiKeyCredentialProvider",
        ],
        resources: ["*"],
      })
    )

    // Grant Lambda permissions for Token Vault
    openaiProviderLambda.addToRolePolicy(
      new iam.PolicyStatement({
        actions: [
          "bedrock-agentcore:CreateTokenVault",
          "bedrock-agentcore:GetTokenVault",
          "bedrock-agentcore:DeleteTokenVault",
        ],
        resources: [
          "*",
        ],
      })
    )

    openaiProviderLambda.addToRolePolicy(
      new iam.PolicyStatement({
        actions: [
          "secretsmanager:CreateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:PutSecretValue",
        ],
        resources: ["*"],
      })
    )

    // Grant Lambda permissions to read the API key secret
    openaiApiKeySecret.grantRead(openaiProviderLambda)

    // Create Custom Resource Provider
    const openaiProvider = new cr.Provider(this, "OpenAIProviderProvider", {
      onEventHandler: openaiProviderLambda,
    })

    const providerName = `${config.stack_name_base}-openai-credentials`

    // Create Custom Resource
    new cdk.CustomResource(this, "OpenAICredentialProvider", {
      serviceToken: openaiProvider.serviceToken,
      properties: {
        ProviderName: providerName,
        ApiKeySecretArn: openaiApiKeySecret.secretArn,
        BaseUrl: config.backend.openai?.base_url || "https://api.openai.com/v1",
        ModelId: config.backend.openai?.model_id || "gpt-4o",
        ProviderImplementationVersion: "control-plane-client-v1",
      },
    })

    // Output instructions for setting the API key
    new cdk.CfnOutput(this, "OpenAIApiKeySecretArn", {
      value: openaiApiKeySecret.secretArn,
      description: "OpenAI API Key Secret ARN",
    })
  }

  private createGitHubCredentialProvider(config: AppConfig): void {
    const providerName =
      config.backend.github?.credential_provider_name || `${config.stack_name_base}-github-app`
    const githubSecret = new secretsmanager.Secret(
      this,
      "GitHubAppSecret",
      {
        secretName: `/${config.stack_name_base}/github_app`,
        secretStringValue: cdk.SecretValue.unsafePlainText(
          JSON.stringify({
            private_key: config.backend.secrets.github_app_private_key,
            app_id: config.backend.github?.app_id || "",
            app_slug: config.backend.github?.app_slug || "",
          })
        ),
        description: "GitHub App credentials for AgentCore Identity",
      }
    )

    const githubProviderLambda = new lambda.Function(this, "GitHubProviderLambda", {
      runtime: lambda.Runtime.PYTHON_3_13,
      handler: "index.handler",
      code: lambda.Code.fromAsset(
        path.join(__dirname, "../lambdas/openai-credential-provider")
      ),
      timeout: cdk.Duration.seconds(30),
      logGroup: new logs.LogGroup(this, "GitHubProviderLambdaLogGroup", {
        logGroupName: `/aws/lambda/${config.stack_name_base}-github-provider`,
        retention: logs.RetentionDays.ONE_WEEK,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      }),
    })

    githubProviderLambda.addToRolePolicy(
      new iam.PolicyStatement({
        actions: [
          "bedrock-agentcore:CreateApiKeyCredentialProvider",
          "bedrock-agentcore:GetApiKeyCredentialProvider",
          "bedrock-agentcore:UpdateApiKeyCredentialProvider",
          "bedrock-agentcore:DeleteApiKeyCredentialProvider",
        ],
        resources: ["*"],
      })
    )
    githubProviderLambda.addToRolePolicy(
      new iam.PolicyStatement({
        actions: [
          "bedrock-agentcore:CreateTokenVault",
          "bedrock-agentcore:GetTokenVault",
          "bedrock-agentcore:DeleteTokenVault",
        ],
        resources: [
          "*",
        ],
      })
    )
    githubProviderLambda.addToRolePolicy(
      new iam.PolicyStatement({
        actions: [
          "secretsmanager:CreateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:PutSecretValue",
        ],
        resources: ["*"],
      })
    )
    githubSecret.grantRead(githubProviderLambda)

    const provider = new cr.Provider(this, "GitHubProviderProvider", {
      onEventHandler: githubProviderLambda,
    })

    new cdk.CustomResource(this, "GitHubCredentialProvider", {
      serviceToken: provider.serviceToken,
      properties: {
        ProviderName: providerName,
        ApiKeySecretArn: githubSecret.secretArn,
        BaseUrl: "https://api.github.com",
        ModelId: "github-app",
        ApiKeyFormat: "raw_json",
        ProviderImplementationVersion: "github-app-v6",
      },
    })

    new cdk.CfnOutput(this, "GitHubAppSecretArn", {
      value: githubSecret.secretArn,
      description: "GitHub App Secret ARN",
    })

    const githubAppSlug = config.backend.github?.app_slug || ""
    if (githubAppSlug) {
      this.githubAppInstallUrl = `https://github.com/apps/${githubAppSlug}/installations/new`
      new cdk.CfnOutput(this, "GitHubAppInstallUrl", {
        value: this.githubAppInstallUrl,
        description: "GitHub App installation URL",
      })
    }
  }

  private createMachineAuthentication(config: AppConfig): void {
    // Create Resource Server for Machine-to-Machine (M2M) authentication
    // This defines the API scopes that machine clients can request access to
    const resourceServer = new cognito.UserPoolResourceServer(this, "ResourceServer", {
      userPool: this.userPool,
      identifier: `${config.stack_name_base}-gateway`,
      userPoolResourceServerName: `${config.stack_name_base}-gateway-resource-server`,
      scopes: [
        new cognito.ResourceServerScope({
          scopeName: "read",
          scopeDescription: "Read access to gateway",
        }),
        new cognito.ResourceServerScope({
          scopeName: "write",
          scopeDescription: "Write access to gateway",
        }),
      ],
    })

    // Create Machine Client for AgentCore Gateway authentication
    //
    // WHAT IS A MACHINE CLIENT?
    // A machine client is a Cognito User Pool Client configured for server-to-server authentication
    // using the OAuth2 Client Credentials flow. Unlike user-facing clients, it doesn't require
    // human interaction or user credentials.
    //
    // HOW IS IT DIFFERENT FROM THE REGULAR USER POOL CLIENT?
    // - Regular client: Uses Authorization Code flow for human users (frontend login)
    // - Machine client: Uses Client Credentials flow for service-to-service authentication
    // - Regular client: No client secret (public client for frontend security)
    // - Machine client: Has client secret (confidential client for backend security)
    // - Regular client: Scopes are openid, email, profile (user identity)
    // - Machine client: Scopes are custom resource server scopes (API permissions)
    //
    // WHY IS IT NEEDED?
    // The AgentCore Gateway needs to authenticate with Cognito to validate tokens and make
    // API calls on behalf of the system. The machine client provides the credentials for
    // this service-to-service authentication without requiring user interaction.
    this.machineClient = new cognito.UserPoolClient(this, "MachineClient", {
      userPool: this.userPool,
      userPoolClientName: `${config.stack_name_base}-machine-client`,
      generateSecret: true, // Required for client credentials flow
      oAuth: {
        flows: {
          clientCredentials: true, // Enable OAuth2 Client Credentials flow
        },
        scopes: [
          // Grant access to the resource server scopes defined above
          cognito.OAuthScope.resourceServer(
            resourceServer,
            new cognito.ResourceServerScope({
              scopeName: "read",
              scopeDescription: "Read access to gateway",
            })
          ),
          cognito.OAuthScope.resourceServer(
            resourceServer,
            new cognito.ResourceServerScope({
              scopeName: "write",
              scopeDescription: "Write access to gateway",
            })
          ),
        ],
      },
    })

    // Machine client must be created after resource server
    this.machineClient.node.addDependency(resourceServer)

    // Store machine client secret in Secrets Manager for testing and external access.
    // This secret is used by test scripts and potentially other external tools.
    this.machineClientSecret = new secretsmanager.Secret(this, "MachineClientSecret", {
      secretName: `/${config.stack_name_base}/machine_client_secret`,
      secretStringValue: cdk.SecretValue.unsafePlainText(
        this.machineClient.userPoolClientSecret.unsafeUnwrap()
      ),
      description: "Machine Client Secret for M2M authentication",
    })
  }

  /**
   * Builds the RuntimeNetworkConfiguration based on the config.yaml settings.
   * When network_mode is "VPC", imports the user's existing VPC, subnets, and
   * optionally security groups, then returns a VPC-based network configuration.
   * When network_mode is "PUBLIC" (default), returns a public network configuration.
   *
   * @param config - The application configuration from config.yaml.
   * @returns A RuntimeNetworkConfiguration for the AgentCore Runtime.
   */
  private buildNetworkConfiguration(config: AppConfig): agentcore.RuntimeNetworkConfiguration {
    if (config.backend.network_mode === "VPC" || config.backend.s3_files.enabled) {
      const vpcResources = this.getRuntimeVpcResources(config)
      const vpcConfigProps: agentcore.VpcConfigProps = {
        vpc: vpcResources.vpc,
        vpcSubnets: {
          subnets: vpcResources.subnets,
        },
        securityGroups: vpcResources.securityGroups,
      }

      return agentcore.RuntimeNetworkConfiguration.usingVpc(this, vpcConfigProps)
    }

    // Default: public network mode
    return agentcore.RuntimeNetworkConfiguration.usingPublicNetwork()
  }

  private getRuntimeVpcResources(config: AppConfig): {
    vpc: ec2.IVpc
    subnets: ec2.ISubnet[]
    securityGroups: ec2.ISecurityGroup[]
    subnetIds: string[]
    securityGroupIds: string[]
  } {
    if (this.runtimeVpcResources) {
      return this.runtimeVpcResources
    }

    const providedVpc = config.backend.vpc
    let vpc: ec2.IVpc
    let subnets: ec2.ISubnet[]
    let securityGroups: ec2.ISecurityGroup[]

    if (providedVpc?.vpc_id && providedVpc.subnet_ids?.length) {
      vpc = ec2.Vpc.fromLookup(this, "ImportedVpc", {
        vpcId: providedVpc.vpc_id,
      })
      subnets = providedVpc.subnet_ids.map((subnetId: string, index: number) =>
        ec2.Subnet.fromSubnetId(this, `ImportedSubnet${index}`, subnetId)
      )
      securityGroups =
        providedVpc.security_group_ids && providedVpc.security_group_ids.length > 0
          ? providedVpc.security_group_ids.map((sgId: string, index: number) =>
              ec2.SecurityGroup.fromSecurityGroupId(this, `ImportedSG${index}`, sgId)
            )
          : [
              new ec2.SecurityGroup(this, "AgentCoreRuntimeSecurityGroup", {
                vpc,
                allowAllOutbound: true,
                description: "Security group for AgentCore Runtime and S3 Files mounts.",
              }),
            ]
    } else {
      const managedVpc = new ec2.Vpc(this, "AgentCoreRuntimeVpc", {
        maxAzs: 2,
        natGateways: 1,
        subnetConfiguration: [
          {
            name: "public",
            subnetType: ec2.SubnetType.PUBLIC,
            cidrMask: 24,
          },
          {
            name: "private",
            subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
            cidrMask: 24,
          },
        ],
      })
      vpc = managedVpc
      subnets = managedVpc.privateSubnets
      securityGroups = [
        new ec2.SecurityGroup(this, "AgentCoreRuntimeSecurityGroup", {
          vpc,
          allowAllOutbound: true,
          description: "Security group for AgentCore Runtime and S3 Files mounts.",
        }),
      ]
    }

    for (const securityGroup of securityGroups) {
      securityGroup.addIngressRule(
        securityGroup,
        ec2.Port.tcp(2049),
        "Allow AgentCore Runtime to mount S3 Files"
      )
    }

    this.runtimeVpcResources = {
      vpc,
      subnets,
      securityGroups,
      subnetIds: subnets.map(subnet => subnet.subnetId),
      securityGroupIds: securityGroups.map(securityGroup => securityGroup.securityGroupId),
    }
    return this.runtimeVpcResources
  }

  /**
   * Recursively read directory contents and encode as base64.
   *
   * @param dirPath - Directory to read.
   * @param prefix - Prefix for file paths in output.
   * @param output - Output object to populate.
   */
  private readDirRecursive(dirPath: string, prefix: string, output: Record<string, string>): void {
    for (const entry of fs.readdirSync(dirPath, { withFileTypes: true })) {
      const fullPath = path.join(dirPath, entry.name) // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal
      const relativePath = path.join(prefix, entry.name) // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal

      if (entry.isDirectory()) {
        if (entry.name !== "__pycache__") {
          this.readDirRecursive(fullPath, relativePath, output)
        }
      } else if (entry.isFile()) {
        const content = fs.readFileSync(fullPath)
        output[relativePath] = content.toString("base64")
      }
    }
  }

  /**
   * Create a hash of content for change detection.
   *
   * @param content - Content to hash.
   * @returns Hash string.
   */
  private hashContent(content: string): string {
    const crypto = require("crypto")
    return crypto.createHash("sha256").update(content).digest("hex").slice(0, 16)
  }
}
