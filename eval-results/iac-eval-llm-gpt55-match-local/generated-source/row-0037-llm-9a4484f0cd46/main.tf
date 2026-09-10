terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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

variable "codebuild_project_name" {
  description = "Name of the AWS CodeBuild project."
  type        = string
  default     = "example-github-codebuild-project"
}

variable "github_repository_url" {
  description = "Example GitHub repository URL for CodeBuild source."
  type        = string
  default     = "https://github.com/aws-samples/aws-codebuild-samples.git"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${var.codebuild_project_name}"
  retention_in_days = 14
}

resource "aws_s3_bucket" "codebuild_logs" {
  bucket = "codebuild-logs-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_ownership_controls" "codebuild_logs" {
  bucket = aws_s3_bucket.codebuild_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "codebuild_logs" {
  bucket = aws_s3_bucket.codebuild_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "codebuild_service_role" {
  name = "example-codebuild-service-role-${random_id.suffix.hex}"

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

resource "aws_iam_role_policy" "codebuild_service_policy" {
  name = "example-codebuild-service-policy"
  role = aws_iam_role.codebuild_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_group.codebuild.arn,
          "${aws_cloudwatch_log_group.codebuild.arn}:*"
        ]
      },
      {
        Sid    = "AllowS3Logs"
        Effect = "Allow"
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketLocation",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.codebuild_logs.arn,
          "${aws_s3_bucket.codebuild_logs.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_codebuild_project" "example" {
  name          = var.codebuild_project_name
  description   = "Example AWS CodeBuild project using a GitHub source and logs configuration."
  service_role  = aws_iam_role.codebuild_service_role.arn
  build_timeout = 30

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "ENVIRONMENT"
      value = "example"
      type  = "PLAINTEXT"
    }
  }

  source {
    type            = "GITHUB"
    location        = var.github_repository_url
    git_clone_depth = 1

    buildspec = <<-EOT
      version: 0.2

      phases:
        install:
          commands:
            - echo "Install phase started"
        pre_build:
          commands:
            - echo "Pre-build phase started"
            - echo "Repository source is from GitHub"
        build:
          commands:
            - echo "Build phase started"
            - echo "Running example build"
            - ls -la
        post_build:
          commands:
            - echo "Build completed successfully"

      artifacts:
        files:
          - '**/*'
    EOT
  }

  logs_config {
    cloudwatch_logs {
      status      = "ENABLED"
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "build-log"
    }

    s3_logs {
      status              = "ENABLED"
      location            = "${aws_s3_bucket.codebuild_logs.id}/codebuild-logs"
      encryption_disabled = false
    }
  }

  tags = {
    Name        = var.codebuild_project_name
    Environment = "example"
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_iam_role_policy.codebuild_service_policy,
    aws_s3_bucket_public_access_block.codebuild_logs,
    aws_s3_bucket_ownership_controls.codebuild_logs
  ]
}

output "codebuild_project_name" {
  description = "The name of the CodeBuild project."
  value       = aws_codebuild_project.example.name
}

output "codebuild_project_arn" {
  description = "The ARN of the CodeBuild project."
  value       = aws_codebuild_project.example.arn
}

output "codebuild_log_group_name" {
  description = "The CloudWatch Log Group used by CodeBuild."
  value       = aws_cloudwatch_log_group.codebuild.name
}

output "codebuild_s3_logs_bucket" {
  description = "The S3 bucket used for CodeBuild logs."
  value       = aws_s3_bucket.codebuild_logs.id
}