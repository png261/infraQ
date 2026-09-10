terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  name_prefix = "iac-eval-codebuild-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
}

resource "aws_s3_bucket" "source" {
  bucket        = "${local.name_prefix}-source"
  force_destroy = true
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.name_prefix}-artifacts"
  force_destroy = true
}

resource "aws_iam_role" "codebuild" {
  name = "iac-eval-codebuild-role"

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
  name = "iac-eval-codebuild-policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.source.arn}/*",
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.source.arn,
          aws_s3_bucket.artifacts.arn
        ]
      }
    ]
  })
}

resource "aws_codebuild_project" "example" {
  name         = "iac-eval-example-project"
  description  = "Example CodeBuild project with environment variables, secondary sources, and secondary artifacts."
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.artifacts.bucket
    path      = "primary"
    packaging = "ZIP"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "EXAMPLE_ENV"
      value = "benchmark"
      type  = "PLAINTEXT"
    }
  }

  source {
    type      = "S3"
    location  = "${aws_s3_bucket.source.bucket}/primary-source.zip"
    buildspec = <<-EOT
      version: 0.2
      phases:
        build:
          commands:
            - echo "Running benchmark build"
      artifacts:
        files:
          - '**/*'
        secondary-artifacts:
          secondary_output:
            files:
              - '**/*'
    EOT
  }

  secondary_sources {
    source_identifier = "secondary_source"
    type              = "S3"
    location          = "${aws_s3_bucket.source.bucket}/secondary-source.zip"
  }

  secondary_artifacts {
    artifact_identifier = "secondary_output"
    type                = "S3"
    location            = aws_s3_bucket.artifacts.bucket
    path                = "secondary"
    packaging           = "ZIP"
  }

  depends_on = [aws_iam_role_policy.codebuild]
}
