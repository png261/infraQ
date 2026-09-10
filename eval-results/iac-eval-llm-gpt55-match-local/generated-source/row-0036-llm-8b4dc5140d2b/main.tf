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

variable "project_name" {
  description = "Name of the AWS CodeBuild project."
  type        = string
  default     = "example-github-codebuild-project"
}

variable "github_repository_url" {
  description = "Example GitHub repository URL used as CodeBuild source."
  type        = string
  default     = "https://github.com/aws-samples/aws-codebuild-samples.git"
}

resource "aws_s3_bucket" "codebuild_artifacts" {
  bucket_prefix = "example-codebuild-artifacts-"

  tags = {
    Name        = "example-codebuild-artifacts"
    Environment = "example"
  }
}

resource "aws_s3_bucket_public_access_block" "codebuild_artifacts" {
  bucket = aws_s3_bucket.codebuild_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "codebuild_artifacts" {
  bucket = aws_s3_bucket.codebuild_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "codebuild_role" {
  name = "${var.project_name}-role"

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
    Name        = "${var.project_name}-role"
    Environment = "example"
  }
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
        Resource = "*"
      },
      {
        Sid    = "S3ArtifactAndCacheAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:GetBucketAcl",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.codebuild_artifacts.arn,
          "${aws_s3_bucket.codebuild_artifacts.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "codebuild_logs" {
  name              = "/aws/codebuild/${var.project_name}"
  retention_in_days = 14

  tags = {
    Name        = "/aws/codebuild/${var.project_name}"
    Environment = "example"
  }
}

resource "aws_codebuild_project" "example" {
  name          = var.project_name
  description   = "Example AWS CodeBuild project using GitHub source, S3 artifacts, and S3 cache."
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 30

  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.codebuild_artifacts.bucket
    path      = "artifacts"
    namespace_type = "BUILD_ID"
    name      = "build-output.zip"
    packaging = "ZIP"
  }

  cache {
    type     = "S3"
    location = "${aws_s3_bucket.codebuild_artifacts.bucket}/cache"
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

    buildspec = <<-EOF
      version: 0.2

      phases:
        install:
          runtime-versions:
            nodejs: 20
          commands:
            - echo "Install phase started"
        pre_build:
          commands:
            - echo "Pre-build phase started"
        build:
          commands:
            - echo "Build phase started"
            - echo "Hello from AWS CodeBuild" > build-output.txt
        post_build:
          commands:
            - echo "Post-build phase completed"

      artifacts:
        files:
          - build-output.txt

      cache:
        paths:
          - '/root/.npm/**/*'
    EOF
  }

  logs_config {
    cloudwatch_logs {
      status      = "ENABLED"
      group_name  = aws_cloudwatch_log_group.codebuild_logs.name
      stream_name = "build-log"
    }

    s3_logs {
      status   = "DISABLED"
      location = null
    }
  }

  tags = {
    Name        = var.project_name
    Environment = "example"
  }

  depends_on = [
    aws_iam_role_policy.codebuild_policy,
    aws_s3_bucket_public_access_block.codebuild_artifacts,
    aws_s3_bucket_versioning.codebuild_artifacts
  ]
}