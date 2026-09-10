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
  description = "AWS region where the CodeBuild project will be created."
  type        = string
  default     = "us-east-1"
}

variable "codebuild_project_name" {
  description = "Name of the AWS CodeBuild project."
  type        = string
  default     = "example-github-codebuild-project"
}

variable "github_repository_url" {
  description = "GitHub repository HTTPS URL used as the CodeBuild source."
  type        = string
  default     = "https://github.com/aws-samples/aws-codebuild-samples.git"
}

resource "aws_iam_role" "codebuild_service_role" {
  name = "example-codebuild-service-role"

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
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:*:log-group:/aws/codebuild/${var.codebuild_project_name}",
          "arn:aws:logs:${var.aws_region}:*:log-group:/aws/codebuild/${var.codebuild_project_name}:*"
        ]
      },
      {
        Sid    = "CodeBuildReportAccess"
        Effect = "Allow"
        Action = [
          "codebuild:CreateReportGroup",
          "codebuild:CreateReport",
          "codebuild:UpdateReport",
          "codebuild:BatchPutTestCases",
          "codebuild:BatchPutCodeCoverages"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_codebuild_project" "github_example" {
  name          = var.codebuild_project_name
  description   = "Example AWS CodeBuild project using a GitHub source repository."
  service_role  = aws_iam_role.codebuild_service_role.arn
  build_timeout = 30

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "EXAMPLE_ENV"
      value = "example-value"
      type  = "PLAINTEXT"
    }
  }

  source {
    type            = "GITHUB"
    location        = var.github_repository_url
    git_clone_depth = 1
    buildspec       = "buildspec.yml"
  }

  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }
  }

  tags = {
    Name        = var.codebuild_project_name
    Environment = "example"
    ManagedBy   = "terraform"
  }
}

output "codebuild_project_name" {
  description = "The name of the created CodeBuild project."
  value       = aws_codebuild_project.github_example.name
}

output "codebuild_project_arn" {
  description = "The ARN of the created CodeBuild project."
  value       = aws_codebuild_project.github_example.arn
}

output "codebuild_service_role_arn" {
  description = "The ARN of the IAM role used by CodeBuild."
  value       = aws_iam_role.codebuild_service_role.arn
}