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

############################
# Variables
############################

variable "aws_region" {
  description = "AWS region to deploy the autograder infrastructure."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for autograder resources."
  type        = string
  default     = "cs-autograder"
}

variable "github_repo_url" {
  description = "GitHub repository URL containing the student code or autograder harness."
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
  default     = "10.40.0.0/16"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private CodeBuild subnet."
  type        = string
  default     = "10.40.1.0/24"
}

############################
# Data Sources
############################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.aws_region}.s3"
}

############################
# Random suffix for globally unique S3 bucket
############################

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

############################
# S3 Bucket for Autograder Results
############################

resource "aws_s3_bucket" "results" {
  bucket = "${var.project_name}-results-${data.aws_caller_identity.current.account_id}-${random_id.bucket_suffix.hex}"

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

############################
# Isolated VPC
############################

resource "aws_vpc" "autograder" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = "autograder"
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.autograder.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.project_name}-private-subnet"
    Environment = "autograder"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.autograder.id

  tags = {
    Name        = "${var.project_name}-private-route-table"
    Environment = "autograder"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

############################
# S3 Gateway Endpoint
#
# This permits private S3 access without giving
# student code general internet access.
############################

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.autograder.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccessOnlyToAutograderResultsBucket"
        Effect = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:AbortMultipartUpload",
          "s3:ListBucketMultipartUploads",
          "s3:ListMultipartUploadParts"
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

############################
# Security Group
#
# No ingress is allowed.
# Egress is limited to HTTPS traffic destined for the
# AWS S3 prefix list only. There is no route to the internet.
############################

resource "aws_security_group" "codebuild" {
  name        = "${var.project_name}-codebuild-sg"
  description = "Restrictive security group for isolated CodeBuild autograder jobs"
  vpc_id      = aws_vpc.autograder.id

  tags = {
    Name        = "${var.project_name}-codebuild-sg"
    Environment = "autograder"
  }
}

resource "aws_vpc_security_group_egress_rule" "codebuild_to_s3_https" {
  security_group_id = aws_security_group.codebuild.id
  description       = "Allow HTTPS egress only to Amazon S3 through the S3 Gateway Endpoint"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_prefix_list.s3.id
}

############################
# CloudWatch Log Group
############################

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${var.project_name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-logs"
    Environment = "autograder"
  }
}

############################
# IAM Role for CodeBuild
############################

resource "aws_iam_role" "codebuild" {
  name = "${var.project_name}-codebuild-role"

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
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogGroup"
        ]
        Resource = [
          aws_cloudwatch_log_group.codebuild.arn,
          "${aws_cloudwatch_log_group.codebuild.arn}:*"
        ]
      },
      {
        Sid    = "AutograderS3ResultsAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:AbortMultipartUpload",
          "s3:ListBucketMultipartUploads",
          "s3:ListMultipartUploadParts"
        ]
        Resource = [
          aws_s3_bucket.results.arn,
          "${aws_s3_bucket.results.arn}/*"
        ]
      },
      {
        Sid    = "CodeBuildVpcNetworkInterfaceManagement"
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
            "ec2:Subnet" = aws_subnet.private.arn
          }
        }
      }
    ]
  })
}

############################
# CodeBuild Project
############################

resource "aws_codebuild_project" "autograder" {
  name         = var.project_name
  description  = "Isolated CS class autograder. Runs student code from GitHub without internet egress."
  service_role = aws_iam_role.codebuild.arn

  build_timeout = 30
  queued_timeout = 30

  source {
    type            = "GITHUB"
    location        = var.github_repo_url
    git_clone_depth = 1
    buildspec       = "buildspec.yml"

    git_submodules_config {
      fetch_submodules = false
    }
  }

  source_version = var.github_branch

  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.results.bucket
    path      = "artifacts"
    namespace_type = "BUILD_ID"
    packaging = "ZIP"
  }

  cache {
    type = "NO_CACHE"
  }

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
      name  = "NO_INTERNET_POLICY"
      value = "CodeBuild runs in a private subnet with no IGW/NAT; egress is restricted to S3 only."
      type  = "PLAINTEXT"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "autograder"
      status      = "ENABLED"
    }

    s3_logs {
      status   = "ENABLED"
      location = "${aws_s3_bucket.results.id}/logs"
    }
  }

  vpc_config {
    vpc_id             = aws_vpc.autograder.id
    subnets            = [aws_subnet.private.id]
    security_group_ids = [aws_security_group.codebuild.id]
  }

  tags = {
    Name        = var.project_name
    Environment = "autograder"
  }

  depends_on = [
    aws_iam_role_policy.codebuild,
    aws_vpc_endpoint.s3,
    aws_route_table_association.private
  ]
}

############################
# Outputs
############################

output "results_bucket_name" {
  description = "S3 bucket where autograder artifacts, logs, and results are stored."
  value       = aws_s3_bucket.results.bucket
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild autograder project."
  value       = aws_codebuild_project.autograder.name
}

output "vpc_id" {
  description = "ID of the isolated autograder VPC."
  value       = aws_vpc.autograder.id
}

output "private_subnet_id" {
  description = "ID of the private subnet used by CodeBuild."
  value       = aws_subnet.private.id
}

output "security_group_id" {
  description = "Security group enforcing restricted autograder egress."
  value       = aws_security_group.codebuild.id
}