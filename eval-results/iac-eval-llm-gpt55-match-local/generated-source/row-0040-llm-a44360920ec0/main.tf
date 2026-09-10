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

resource "aws_s3_bucket" "codebuild_artifacts" {
  bucket = "example-codebuild-artifacts-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
}

resource "aws_s3_bucket_public_access_block" "codebuild_artifacts" {
  bucket = aws_s3_bucket.codebuild_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "codebuild_role" {
  name = "example-codebuild-batch-role"

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
  name = "example-codebuild-batch-policy"
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
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/example-batch-project",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/example-batch-project:*"
        ]
      },
      {
        Sid    = "S3ArtifactsAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:GetBucketAcl",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.codebuild_artifacts.arn,
          "${aws_s3_bucket.codebuild_artifacts.arn}/*"
        ]
      },
      {
        Sid    = "CodeBuildBatchAccess"
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
          "codebuild:StopBuild",
          "codebuild:RetryBuild",
          "codebuild:BatchGetBuilds"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_codebuild_project" "example" {
  name          = "example-batch-project"
  description   = "Example AWS CodeBuild project with build batch configuration"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 30

  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.codebuild_artifacts.bucket
    packaging = "NONE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "EXAMPLE_ENV"
      value = "hello-from-codebuild"
      type  = "PLAINTEXT"
    }
  }

  source {
    type = "NO_SOURCE"

    buildspec = <<-EOF
      version: 0.2

      batch:
        fast-fail: false
        build-list:
          - identifier: build_ubuntu
            buildspec: |
              version: 0.2
              phases:
                build:
                  commands:
                    - echo "Running batch build ubuntu example"
                    - echo "$EXAMPLE_ENV"
          - identifier: build_test
            buildspec: |
              version: 0.2
              phases:
                build:
                  commands:
                    - echo "Running batch build test example"
                    - date

      phases:
        install:
          commands:
            - echo "Install phase"
        build:
          commands:
            - echo "Main build phase"
            - echo "This project supports AWS CodeBuild batch builds"

      artifacts:
        files:
          - '**/*'
    EOF
  }

  logs_config {
    cloudwatch_logs {
      status      = "ENABLED"
      group_name  = "/aws/codebuild/example-batch-project"
      stream_name = "build-log"
    }
  }

  build_batch_config {
    service_role    = aws_iam_role.codebuild_role.arn
    timeout_in_mins = 60

    restrictions {
      maximum_builds_allowed = 4
      compute_types_allowed = [
        "BUILD_GENERAL1_SMALL"
      ]
    }
  }

  tags = {
    Name        = "example-batch-project"
    Environment = "example"
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_iam_role_policy.codebuild_policy,
    aws_s3_bucket_public_access_block.codebuild_artifacts
  ]
}