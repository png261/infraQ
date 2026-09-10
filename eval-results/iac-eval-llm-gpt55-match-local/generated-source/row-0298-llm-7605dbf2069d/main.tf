terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

############################################################
# Variables
############################################################

variable "aws_region" {
  description = "AWS region to deploy the autograder infrastructure into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for the autograder resources."
  type        = string
  default     = "cs-autograder"
}

variable "github_repo_url" {
  description = "GitHub repository URL containing the autograder and student code."
  type        = string
  default     = "https://github.com/example-org/example-autograder-repo.git"
}

variable "github_branch" {
  description = "GitHub branch to build."
  type        = string
  default     = "main"
}

variable "vpc_cidr" {
  description = "CIDR block for the isolated autograder VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "private_subnet_a_cidr" {
  description = "CIDR block for private subnet A."
  type        = string
  default     = "10.42.1.0/24"
}

variable "private_subnet_b_cidr" {
  description = "CIDR block for private subnet B."
  type        = string
  default     = "10.42.2.0/24"
}

############################################################
# Data Sources
############################################################

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.aws_region}.s3"
}

############################################################
# Networking: VPC with private subnets only
############################################################

resource "aws_vpc" "autograder" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = "autograder"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.autograder.id
  cidr_block              = var.private_subnet_a_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.project_name}-private-a"
    Environment = "autograder"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.autograder.id
  cidr_block              = var.private_subnet_b_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.project_name}-private-b"
    Environment = "autograder"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.autograder.id

  tags = {
    Name        = "${var.project_name}-private-rt"
    Environment = "autograder"
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

############################################################
# S3 bucket for autograder results
############################################################

resource "aws_s3_bucket" "results" {
  bucket = "${var.project_name}-results-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  tags = {
    Name        = "${var.project_name}-results"
    Environment = "autograder"
  }
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket = aws_s3_bucket.results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "results" {
  bucket = aws_s3_bucket.results.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    id     = "expire-old-autograder-results"
    status = "Enabled"

    filter {
      prefix = "results/"
    }

    expiration {
      days = 180
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

############################################################
# VPC Endpoints
#
# No Internet Gateway or NAT Gateway is created.
# CodeBuild can only reach explicitly allowed AWS services.
############################################################

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.autograder.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.private.id
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCodeBuildAccessToResultsBucketOnly"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.codebuild.arn
        }
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.results.arn,
          "${aws_s3_bucket.results.arn}/*"
        ]
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-s3-endpoint"
    Environment = "autograder"
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-vpc-endpoints-sg"
  description = "Security group for VPC interface endpoints used by CodeBuild."
  vpc_id      = aws_vpc.autograder.id

  ingress {
    description     = "Allow HTTPS from CodeBuild"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.codebuild.id]
  }

  egress {
    description = "Allow endpoint responses within the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name        = "${var.project_name}-vpc-endpoints-sg"
    Environment = "autograder"
  }
}

resource "aws_vpc_endpoint" "cloudwatch_logs" {
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
    Name        = "${var.project_name}-logs-endpoint"
    Environment = "autograder"
  }
}

############################################################
# Security group for CodeBuild
#
# Outbound traffic is restricted:
# - HTTPS to S3 via the S3 managed prefix list.
# - HTTPS to CloudWatch Logs interface endpoint inside the VPC.
#
# There is no default 0.0.0.0/0 egress rule.
############################################################

resource "aws_security_group" "codebuild" {
  name        = "${var.project_name}-codebuild-sg"
  description = "Restricted security group for isolated CodeBuild autograder jobs."
  vpc_id      = aws_vpc.autograder.id

  tags = {
    Name        = "${var.project_name}-codebuild-sg"
    Environment = "autograder"
  }
}

resource "aws_security_group_rule" "codebuild_egress_s3" {
  type              = "egress"
  description       = "Allow HTTPS only to Amazon S3 through the regional S3 prefix list."
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.codebuild.id
  prefix_list_ids   = [data.aws_prefix_list.s3.id]
}

resource "aws_security_group_rule" "codebuild_egress_logs_endpoint" {
  type                     = "egress"
  description              = "Allow HTTPS to CloudWatch Logs VPC endpoint."
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.codebuild.id
  source_security_group_id = aws_security_group.vpc_endpoints.id
}

############################################################
# CloudWatch Logs
############################################################

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${var.project_name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-logs"
    Environment = "autograder"
  }
}

############################################################
# IAM Role for CodeBuild
############################################################

resource "aws_iam_role" "codebuild" {
  name = "${var.project_name}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCodeBuildAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-codebuild-role"
    Environment = "autograder"
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${var.project_name}-codebuild-policy"
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
        Sid    = "ResultsBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.results.arn,
          "${aws_s3_bucket.results.arn}/*"
        ]
      },
      {
        Sid    = "CodeBuildVpcNetworkInterfaceAccess"
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
        Sid    = "CodeBuildCreateNetworkInterfacePermission"
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

############################################################
# CodeBuild Project
############################################################

resource "aws_codebuild_project" "autograder" {
  name          = var.project_name
  description   = "Isolated CodeBuild autograder for running student submissions without internet access."
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  artifacts {
    type = "NO_ARTIFACTS"
  }

  source {
    type            = "GITHUB"
    location        = var.github_repo_url
    git_clone_depth = 1
    buildspec       = "buildspec.yml"
  }

  source_version = var.github_branch

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "RESULTS_BUCKET"
      value = aws_s3_bucket.results.bucket
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "RESULTS_PREFIX"
      value = "results"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "NO_INTERNET_EXPECTED"
      value = "true"
      type  = "PLAINTEXT"
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

  logs_config {
    cloudwatch_logs {
      status      = "ENABLED"
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "autograder"
    }
  }

  tags = {
    Name        = var.project_name
    Environment = "autograder"
  }

  depends_on = [
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.cloudwatch_logs,
    aws_iam_role_policy.codebuild
  ]
}

############################################################
# Example Buildspec
#
# This local file is included to document the expected buildspec
# in the GitHub repository. The CodeBuild project itself expects
# buildspec.yml to exist in the configured GitHub repository.
############################################################

resource "local_file" "example_buildspec" {
  filename = "${path.module}/example-buildspec.yml"

  content = <<-YAML
    version: 0.2

    phases:
      install:
        commands:
          - echo "Installing dependencies already present in the CodeBuild image."
          - echo "Because this build runs in a private VPC with no NAT or Internet Gateway, student code cannot access the public internet."

      pre_build:
        commands:
          - echo "Starting autograder run"
          - mkdir -p autograder-output

      build:
        commands:
          - echo "Run your course-specific autograder here."
          - |
            if [ -x "./run_tests.sh" ]; then
              ./run_tests.sh > autograder-output/results.txt 2>&1
            else
              echo "No executable run_tests.sh found." > autograder-output/results.txt
              echo "Create a run_tests.sh script in the GitHub repository to perform grading." >> autograder-output/results.txt
            fi

      post_build:
        commands:
          - echo "Uploading results to S3"
          - aws s3 cp autograder-output/results.txt "s3://$RESULTS_BUCKET/$RESULTS_PREFIX/$CODEBUILD_BUILD_ID/results.txt"
          - echo "Results uploaded to s3://$RESULTS_BUCKET/$RESULTS_PREFIX/$CODEBUILD_BUILD_ID/results.txt"
  YAML
}

############################################################
# Outputs
############################################################

output "codebuild_project_name" {
  description = "Name of the CodeBuild autograder project."
  value       = aws_codebuild_project.autograder.name
}

output "results_bucket_name" {
  description = "S3 bucket where autograder results are stored."
  value       = aws_s3_bucket.results.bucket
}

output "vpc_id" {
  description = "ID of the isolated autograder VPC."
  value       = aws_vpc.autograder.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by CodeBuild."
  value = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]
}

output "internet_access_prevention_summary" {
  description = "Explanation of how internet access is prevented."
  value       = "The VPC has no Internet Gateway, no NAT Gateway, private subnets only, and the CodeBuild security group only allows HTTPS egress to S3 and the CloudWatch Logs VPC endpoint."
}