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

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the CodeBuild project."
  type        = string
  default     = "example-github-codebuild-project"
}

variable "github_repo_url" {
  description = "GitHub repository URL used as the CodeBuild source."
  type        = string
  default     = "https://github.com/aws-samples/aws-codebuild-samples.git"
}

variable "github_source_version" {
  description = "GitHub branch, tag, or commit to build."
  type        = string
  default     = "main"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  cache_bucket_name = "codebuild-cache-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
}

resource "aws_s3_bucket" "codebuild_cache" {
  bucket = local.cache_bucket_name
}

resource "aws_s3_bucket_public_access_block" "codebuild_cache" {
  bucket = aws_s3_bucket.codebuild_cache.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "codebuild_cache" {
  bucket = aws_s3_bucket.codebuild_cache.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role" "codebuild_role" {
  name = "${var.project_name}-service-role"

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

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "${var.project_name}-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_name}",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_name}:*"
        ]
      },
      {
        Sid    = "S3CacheAccess"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.codebuild_cache.arn,
          "${aws_s3_bucket.codebuild_cache.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_codebuild_project" "example" {
  name          = var.project_name
  description   = "Example CodeBuild project using GitHub source, environment variables, IAM role, and S3 cache."
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 30

  artifacts {
    type = "NO_ARTIFACTS"
  }

  source {
    type            = "GITHUB"
    location        = var.github_repo_url
    git_clone_depth = 1

    buildspec = <<-EOT
      version: 0.2

      phases:
        install:
          commands:
            - echo "Installing dependencies..."
        pre_build:
          commands:
            - echo "Pre-build phase"
            - echo "Environment: $ENVIRONMENT"
            - echo "Application: $APP_NAME"
        build:
          commands:
            - echo "Build started on $(date)"
            - echo "Running example build commands"
            - ls -la
        post_build:
          commands:
            - echo "Build completed on $(date)"

      cache:
        paths:
          - '/root/.cache/**/*'
          - 'node_modules/**/*'
    EOT
  }

  source_version = var.github_source_version

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "ENVIRONMENT"
      value = "dev"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "APP_NAME"
      value = "example-app"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "LOG_LEVEL"
      value = "info"
      type  = "PLAINTEXT"
    }
  }

  cache {
    type     = "S3"
    location = "${aws_s3_bucket.codebuild_cache.bucket}/codebuild-cache"
  }

  logs_config {
    cloudwatch_logs {
      status      = "ENABLED"
      group_name  = "/aws/codebuild/${var.project_name}"
      stream_name = "build-log"
    }
  }

  tags = {
    Name        = var.project_name
    Environment = "dev"
    ManagedBy   = "Terraform"
  }

  depends_on = [
    aws_iam_role_policy.codebuild_policy,
    aws_s3_bucket_public_access_block.codebuild_cache,
    aws_s3_bucket_server_side_encryption_configuration.codebuild_cache
  ]
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild project."
  value       = aws_codebuild_project.example.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project."
  value       = aws_codebuild_project.example.arn
}

output "cache_bucket_name" {
  description = "Name of the S3 bucket used for CodeBuild cache."
  value       = aws_s3_bucket.codebuild_cache.bucket
}