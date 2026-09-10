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
  region = "us-east-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_prefix = "example-codebuild-${random_id.suffix.hex}"
}

resource "aws_s3_bucket" "source_bucket" {
  bucket = "${local.name_prefix}-sources"
}

resource "aws_s3_bucket" "artifact_bucket" {
  bucket = "${local.name_prefix}-artifacts"
}

resource "aws_s3_bucket_versioning" "source_bucket_versioning" {
  bucket = aws_s3_bucket.source_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "artifact_bucket_versioning" {
  bucket = aws_s3_bucket.artifact_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${local.name_prefix}"
  retention_in_days = 14
}

resource "aws_iam_role" "codebuild_role" {
  name = "${local.name_prefix}-role"

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
  name = "${local.name_prefix}-policy"
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
          aws_cloudwatch_log_group.codebuild.arn,
          "${aws_cloudwatch_log_group.codebuild.arn}:*"
        ]
      },
      {
        Sid    = "S3SourceAndArtifactAccess"
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
          aws_s3_bucket.source_bucket.arn,
          "${aws_s3_bucket.source_bucket.arn}/*",
          aws_s3_bucket.artifact_bucket.arn,
          "${aws_s3_bucket.artifact_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_codebuild_project" "example" {
  name          = local.name_prefix
  description   = "Example CodeBuild project with IAM role, environment variables, secondary sources, and secondary artifacts."
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 30

  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.artifact_bucket.bucket
    name      = "primary-artifact.zip"
    packaging = "ZIP"
  }

  secondary_artifacts {
    artifact_identifier = "secondary_artifact_one"
    type                = "S3"
    location            = aws_s3_bucket.artifact_bucket.bucket
    name                = "secondary-artifact-one.zip"
    packaging           = "ZIP"
  }

  secondary_artifacts {
    artifact_identifier = "secondary_artifact_two"
    type                = "S3"
    location            = aws_s3_bucket.artifact_bucket.bucket
    name                = "secondary-artifact-two.zip"
    packaging           = "ZIP"
  }

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
      name  = "ARTIFACT_BUCKET"
      value = aws_s3_bucket.artifact_bucket.bucket
      type  = "PLAINTEXT"
    }
  }

  source {
    type     = "S3"
    location = "${aws_s3_bucket.source_bucket.bucket}/primary-source.zip"

    buildspec = <<-EOT
      version: 0.2

      phases:
        install:
          commands:
            - echo "Installing dependencies"
        pre_build:
          commands:
            - echo "Pre-build phase"
            - echo "Environment is $ENVIRONMENT"
            - echo "Application is $APP_NAME"
        build:
          commands:
            - echo "Build started"
            - mkdir -p output secondary-one secondary-two
            - echo "Primary artifact content" > output/primary.txt
            - echo "Secondary artifact one content" > secondary-one/artifact-one.txt
            - echo "Secondary artifact two content" > secondary-two/artifact-two.txt
        post_build:
          commands:
            - echo "Build completed"

      artifacts:
        files:
          - output/**/*
        secondary-artifacts:
          secondary_artifact_one:
            files:
              - secondary-one/**/*
          secondary_artifact_two:
            files:
              - secondary-two/**/*
    EOT
  }

  secondary_sources {
    source_identifier = "secondary_source_one"
    type              = "S3"
    location          = "${aws_s3_bucket.source_bucket.bucket}/secondary-source-one.zip"
  }

  secondary_sources {
    source_identifier = "secondary_source_two"
    type              = "S3"
    location          = "${aws_s3_bucket.source_bucket.bucket}/secondary-source-two.zip"
  }

  logs_config {
    cloudwatch_logs {
      status      = "ENABLED"
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "build-log"
    }
  }

  depends_on = [
    aws_iam_role_policy.codebuild_policy
  ]
}

output "codebuild_project_name" {
  value = aws_codebuild_project.example.name
}

output "codebuild_role_arn" {
  value = aws_iam_role.codebuild_role.arn
}

output "source_bucket_name" {
  value = aws_s3_bucket.source_bucket.bucket
}

output "artifact_bucket_name" {
  value = aws_s3_bucket.artifact_bucket.bucket
}