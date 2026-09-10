terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the CodeBuild project."
  type        = string
  default     = "cb-secondary-sources"
}

data "aws_caller_identity" "current" {}

locals {
  source_bucket_name = "${var.project_name}-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  primary_source_key    = "sources/primary-source.zip"
  secondary_source_key1 = "sources/secondary-source-one.zip"
  secondary_source_key2 = "sources/secondary-source-two.zip"
}

resource "aws_s3_bucket" "codebuild_sources" {
  bucket        = local.source_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "codebuild_sources" {
  bucket = aws_s3_bucket.codebuild_sources.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "archive_file" "primary_source" {
  type        = "zip"
  output_path = "${path.module}/primary-source.zip"

  source {
    filename = "README.md"
    content  = "# Primary CodeBuild Source\n\nThis is the primary source archive."
  }

  source {
    filename = "app.sh"
    content  = <<-EOT
      #!/bin/sh
      echo "Hello from the primary source."
    EOT
  }
}

data "archive_file" "secondary_source_one" {
  type        = "zip"
  output_path = "${path.module}/secondary-source-one.zip"

  source {
    filename = "README.md"
    content  = "# Secondary Source One\n\nThis is the first secondary source archive."
  }

  source {
    filename = "library-one.txt"
    content  = "Example dependency or shared library from secondary source one."
  }
}

data "archive_file" "secondary_source_two" {
  type        = "zip"
  output_path = "${path.module}/secondary-source-two.zip"

  source {
    filename = "README.md"
    content  = "# Secondary Source Two\n\nThis is the second secondary source archive."
  }

  source {
    filename = "library-two.txt"
    content  = "Example dependency or shared library from secondary source two."
  }
}

resource "aws_s3_object" "primary_source" {
  bucket = aws_s3_bucket.codebuild_sources.id
  key    = local.primary_source_key
  source = data.archive_file.primary_source.output_path
  etag   = data.archive_file.primary_source.output_md5
}

resource "aws_s3_object" "secondary_source_one" {
  bucket = aws_s3_bucket.codebuild_sources.id
  key    = local.secondary_source_key1
  source = data.archive_file.secondary_source_one.output_path
  etag   = data.archive_file.secondary_source_one.output_md5
}

resource "aws_s3_object" "secondary_source_two" {
  bucket = aws_s3_bucket.codebuild_sources.id
  key    = local.secondary_source_key2
  source = data.archive_file.secondary_source_two.output_path
  etag   = data.archive_file.secondary_source_two.output_md5
}

resource "aws_iam_role" "codebuild_service_role" {
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

resource "aws_iam_role_policy" "codebuild_service_policy" {
  name = "${var.project_name}-service-policy"
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
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_name}",
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_name}:*"
        ]
      },
      {
        Sid    = "AllowS3SourceAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.codebuild_sources.arn,
          "${aws_s3_bucket.codebuild_sources.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_codebuild_project" "example" {
  name          = var.project_name
  description   = "Example CodeBuild project with a primary source and secondary sources."
  service_role  = aws_iam_role.codebuild_service_role.arn
  build_timeout = 20

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "S3"
    location  = "${aws_s3_bucket.codebuild_sources.bucket}/${aws_s3_object.primary_source.key}"
    buildspec = <<-EOT
      version: 0.2

      phases:
        install:
          commands:
            - echo "Install phase started"
        pre_build:
          commands:
            - echo "Primary source directory:"
            - echo "$CODEBUILD_SRC_DIR"
            - echo "Secondary source one directory:"
            - echo "$CODEBUILD_SRC_DIR_secondary_one"
            - echo "Secondary source two directory:"
            - echo "$CODEBUILD_SRC_DIR_secondary_two"
        build:
          commands:
            - echo "Listing primary source files"
            - ls -la "$CODEBUILD_SRC_DIR"
            - echo "Listing secondary source one files"
            - ls -la "$CODEBUILD_SRC_DIR_secondary_one"
            - echo "Listing secondary source two files"
            - ls -la "$CODEBUILD_SRC_DIR_secondary_two"
            - echo "Build completed successfully"
    EOT
  }

  secondary_sources {
    type              = "S3"
    location          = "${aws_s3_bucket.codebuild_sources.bucket}/${aws_s3_object.secondary_source_one.key}"
    source_identifier = "secondary_one"
  }

  secondary_sources {
    type              = "S3"
    location          = "${aws_s3_bucket.codebuild_sources.bucket}/${aws_s3_object.secondary_source_two.key}"
    source_identifier = "secondary_two"
  }

  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }
  }

  depends_on = [
    aws_iam_role_policy.codebuild_service_policy,
    aws_s3_object.primary_source,
    aws_s3_object.secondary_source_one,
    aws_s3_object.secondary_source_two
  ]
}

output "codebuild_project_name" {
  description = "Name of the created CodeBuild project."
  value       = aws_codebuild_project.example.name
}

output "codebuild_project_arn" {
  description = "ARN of the created CodeBuild project."
  value       = aws_codebuild_project.example.arn
}

output "source_bucket_name" {
  description = "S3 bucket containing the primary and secondary source archives."
  value       = aws_s3_bucket.codebuild_sources.bucket
}