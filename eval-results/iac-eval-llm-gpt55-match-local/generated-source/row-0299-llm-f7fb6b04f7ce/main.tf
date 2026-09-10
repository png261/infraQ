terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy the autograder infrastructure into."
  type        = string
  default     = "us-east-1"
}

variable "github_repository_url" {
  description = "HTTPS URL of the GitHub repository containing student code or autograder harness."
  type        = string
  default     = "https://github.com/example-org/example-student-repo.git"
}

variable "codebuild_compute_type" {
  description = "Compute size for the CodeBuild autograder environment."
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
}

variable "codebuild_image" {
  description = "Managed CodeBuild image used to run the autograder."
  type        = string
  default     = "aws/codebuild/standard:7.0"
}

variable "project_name" {
  description = "Name prefix for the autograder resources."
  type        = string
  default     = "cs-autograder"
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

random_id "suffix" {
  byte_length = 4
}

locals {
  name_prefix = "${var.project_name}-${random_id.suffix.hex}"
}

resource "aws_s3_bucket" "results" {
  bucket = "${local.name_prefix}-results"

  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket = aws_s3_bucket.results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "results" {
  bucket = aws_s3_bucket.results.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_vpc" "autograder" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.autograder.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.autograder.id
  cidr_block              = "10.40.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-private-b"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.autograder.id

  tags = {
    Name = "${local.name_prefix}-private-rt"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "codebuild" {
  name        = "${local.name_prefix}-codebuild-sg"
  description = "Security group for isolated CodeBuild autograder jobs."
  vpc_id      = aws_vpc.autograder.id

  tags = {
    Name = "${local.name_prefix}-codebuild-sg"
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.name_prefix}-vpc-endpoints-sg"
  description = "Security group for VPC interface endpoints."
  vpc_id      = aws_vpc.autograder.id

  ingress {
    description     = "Allow HTTPS from CodeBuild jobs to VPC endpoints."
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.codebuild.id]
  }

  tags = {
    Name = "${local.name_prefix}-vpc-endpoints-sg"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.autograder.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.private.id
  ]

  tags = {
    Name = "${local.name_prefix}-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.autograder.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  security_group_ids = [
    aws_security_group.vpc_endpoints.id
  ]

  tags = {
    Name = "${local.name_prefix}-logs-endpoint"
  }
}

resource "aws_security_group_rule" "codebuild_egress_to_logs_endpoint" {
  type                     = "egress"
  description              = "Allow CodeBuild to send logs through the CloudWatch Logs VPC endpoint."
  security_group_id        = aws_security_group.codebuild.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vpc_endpoints.id
}

resource "aws_security_group_rule" "codebuild_egress_to_s3_endpoint" {
  type              = "egress"
  description       = "Allow CodeBuild to access S3 only through the S3 gateway endpoint."
  security_group_id = aws_security_group.codebuild.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [aws_vpc_endpoint.s3.prefix_list_id]
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${local.name_prefix}"
  retention_in_days = 30
}

resource "aws_iam_role" "codebuild" {
  name = "${local.name_prefix}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${local.name_prefix}-codebuild-policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:CreateLogGroup",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_group.codebuild.arn,
          "${aws_cloudwatch_log_group.codebuild.arn}:*"
        ]
      },
      {
        Sid    = "S3ResultsAccess"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.results.arn
      },
      {
        Sid    = "S3ResultsObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.results.arn}/*"
      },
      {
        Sid    = "VpcNetworkInterfaceAccess"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeDhcpOptions",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      },
      {
        Sid    = "CodeBuildNetworkInterfacePermission"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterfacePermission"
        ]
        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:network-interface/*"
        Condition = {
          StringEquals = {
            "ec2:AuthorizedService" = "codebuild.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_codebuild_project" "autograder" {
  name          = local.name_prefix
  description   = "Isolated CS class autograder. Runs student GitHub code without internet access and stores results in S3."
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  source {
    type            = "GITHUB"
    location        = var.github_repository_url
    git_clone_depth = 1

    buildspec = <<-EOT
      version: 0.2

      phases:
        install:
          commands:
            - echo "Preparing isolated autograder environment"
            - mkdir -p autograder-results
        pre_build:
          commands:
            - echo "Build started on $(date -u)"
            - echo "Repository source is already checked out by CodeBuild before the isolated build phase."
            - echo "No NAT gateway or Internet Gateway is attached to this VPC, so student code cannot reach the public internet."
        build:
          commands:
            - echo "Running autograder..."
            - |
              set +e
              if [ -f "./run_tests.sh" ]; then
                chmod +x ./run_tests.sh
                ./run_tests.sh > autograder-results/stdout.txt 2> autograder-results/stderr.txt
                TEST_EXIT_CODE=$?
              elif [ -f "./pytest.ini" ] || find . -maxdepth 2 -name "test_*.py" | grep -q .; then
                python -m pytest -q > autograder-results/stdout.txt 2> autograder-results/stderr.txt
                TEST_EXIT_CODE=$?
              else
                echo "No run_tests.sh or pytest tests found." > autograder-results/stdout.txt
                echo "" > autograder-results/stderr.txt
                TEST_EXIT_CODE=2
              fi

              cat > autograder-results/result.json <<EOF
              {
                "project": "${CODEBUILD_PROJECT_NAME}",
                "build_id": "${CODEBUILD_BUILD_ID}",
                "commit": "${CODEBUILD_RESOLVED_SOURCE_VERSION}",
                "exit_code": $TEST_EXIT_CODE,
                "passed": $([ "$TEST_EXIT_CODE" -eq 0 ] && echo true || echo false),
                "completed_at_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
              }
              EOF

              exit 0
        post_build:
          commands:
            - echo "Autograder completed on $(date -u)"
            - cat autograder-results/result.json

      artifacts:
        base-directory: autograder-results
        files:
          - "**/*"
    EOT
  }

  artifacts {
    type                   = "S3"
    location               = aws_s3_bucket.results.bucket
    path                   = "codebuild-artifacts"
    namespace_type         = "BUILD_ID"
    packaging              = "ZIP"
    override_artifact_name = false
    encryption_disabled    = false
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                       = var.codebuild_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "RESULTS_BUCKET"
      value = aws_s3_bucket.results.bucket
      type  = "PLAINTEXT"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "autograder"
      status      = "ENABLED"
    }
  }

  vpc_config {
    vpc_id = aws_vpc.autograder.id

    subnets = [
      aws_subnet.private_a.id,
      aws_subnet.private_b.id
    ]

    security_group_ids = [
      aws_security_group.codebuild.id
    ]
  }

  tags = {
    Name = local.name_prefix
  }

  depends_on = [
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.logs,
    aws_iam_role_policy.codebuild
  ]
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild autograder project."
  value       = aws_codebuild_project.autograder.name
}

output "results_bucket_name" {
  description = "S3 bucket where autograder results are stored."
  value       = aws_s3_bucket.results.bucket
}

output "vpc_id" {
  description = "VPC ID for the isolated autograder environment."
  value       = aws_vpc.autograder.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by the isolated CodeBuild jobs."
  value = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]
}