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
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_iam_role" "codebuild_service_role" {
  name = "example-codebuild-batch-service-role"

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
  name = "example-codebuild-batch-service-policy"
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
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/example-batch-codebuild-project",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/example-batch-codebuild-project:*"
        ]
      },
      {
        Sid    = "CodeBuildBatchAccess"
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
          "codebuild:StopBuild",
          "codebuild:RetryBuild",
          "codebuild:StartBuildBatch",
          "codebuild:StopBuildBatch",
          "codebuild:RetryBuildBatch",
          "codebuild:BatchGetBuilds",
          "codebuild:BatchGetBuildBatches"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_codebuild_project" "example" {
  name          = "example-batch-codebuild-project"
  description   = "Example AWS CodeBuild project with build batch configuration"
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
      name  = "EXAMPLE_ENV"
      value = "example"
      type  = "PLAINTEXT"
    }
  }

  source {
    type = "NO_SOURCE"

    buildspec = <<-EOT
      version: 0.2

      batch:
        fast-fail: false
        build-list:
          - identifier: build_one
            env:
              variables:
                BUILD_NAME: build_one
          - identifier: build_two
            env:
              variables:
                BUILD_NAME: build_two

      phases:
        install:
          commands:
            - echo "Installing dependencies for $BUILD_NAME"
        build:
          commands:
            - echo "Running batch build job $BUILD_NAME"
            - echo "CodeBuild batch example completed"
    EOT
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/example-batch-codebuild-project"
      stream_name = "build-log"
      status      = "ENABLED"
    }
  }

  build_batch_config {
    service_role     = aws_iam_role.codebuild_service_role.arn
    combine_artifacts = false
    timeout_in_mins  = 60

    restrictions {
      maximum_builds_allowed = 4
      compute_types_allowed = [
        "BUILD_GENERAL1_SMALL"
      ]
    }
  }

  tags = {
    Name        = "example-batch-codebuild-project"
    Environment = "example"
  }

  depends_on = [
    aws_iam_role_policy.codebuild_service_policy
  ]
}