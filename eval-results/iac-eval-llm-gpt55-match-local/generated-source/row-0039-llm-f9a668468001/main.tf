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
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the AWS CodeBuild project."
  type        = string
  default     = "example-codebuild-secondary-artifacts"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "primary_artifacts" {
  bucket        = "${var.project_name}-primary-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket" "secondary_artifacts_one" {
  bucket        = "${var.project_name}-secondary-one-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket" "secondary_artifacts_two" {
  bucket        = "${var.project_name}-secondary-two-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "primary_artifacts" {
  bucket = aws_s3_bucket.primary_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "secondary_artifacts_one" {
  bucket = aws_s3_bucket.secondary_artifacts_one.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "secondary_artifacts_two" {
  bucket = aws_s3_bucket.secondary_artifacts_two.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "codebuild_role" {
  name               = "${var.project_name}-role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
}

data "aws_iam_policy_document" "codebuild_policy" {
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowS3ArtifactAccess"
    effect = "Allow"

    actions = [
      "s3:GetBucketAcl",
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.primary_artifacts.arn,
      aws_s3_bucket.secondary_artifacts_one.arn,
      aws_s3_bucket.secondary_artifacts_two.arn
    ]
  }

  statement {
    sid    = "AllowS3ArtifactObjectAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]

    resources = [
      "${aws_s3_bucket.primary_artifacts.arn}/*",
      "${aws_s3_bucket.secondary_artifacts_one.arn}/*",
      "${aws_s3_bucket.secondary_artifacts_two.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name   = "${var.project_name}-policy"
  role   = aws_iam_role.codebuild_role.id
  policy = data.aws_iam_policy_document.codebuild_policy.json
}

resource "aws_codebuild_project" "example" {
  name          = var.project_name
  description   = "Example CodeBuild project with primary and secondary S3 artifacts."
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 20

  artifacts {
    type                = "S3"
    location            = aws_s3_bucket.primary_artifacts.bucket
    packaging           = "ZIP"
    namespace_type      = "BUILD_ID"
    name                = "primary-artifact.zip"
    path                = "primary"
    override_artifact_name = false
  }

  secondary_artifacts {
    artifact_identifier = "secondaryArtifactOne"
    type                = "S3"
    location            = aws_s3_bucket.secondary_artifacts_one.bucket
    packaging           = "ZIP"
    namespace_type      = "BUILD_ID"
    name                = "secondary-artifact-one.zip"
    path                = "secondary-one"
    override_artifact_name = false
  }

  secondary_artifacts {
    artifact_identifier = "secondaryArtifactTwo"
    type                = "S3"
    location            = aws_s3_bucket.secondary_artifacts_two.bucket
    packaging           = "ZIP"
    namespace_type      = "BUILD_ID"
    name                = "secondary-artifact-two.zip"
    path                = "secondary-two"
    override_artifact_name = false
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type = "NO_SOURCE"

    buildspec = <<-EOT
      version: 0.2

      phases:
        build:
          commands:
            - echo "Creating primary and secondary artifact files"
            - mkdir -p primary-output secondary-output-one secondary-output-two
            - echo "This is the primary artifact" > primary-output/primary.txt
            - echo "This is secondary artifact one" > secondary-output-one/secondary-one.txt
            - echo "This is secondary artifact two" > secondary-output-two/secondary-two.txt

      artifacts:
        files:
          - primary-output/**/*
        secondary-artifacts:
          secondaryArtifactOne:
            files:
              - secondary-output-one/**/*
          secondaryArtifactTwo:
            files:
              - secondary-output-two/**/*
    EOT
  }

  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }
  }

  depends_on = [
    aws_iam_role_policy.codebuild_policy,
    aws_s3_bucket_public_access_block.primary_artifacts,
    aws_s3_bucket_public_access_block.secondary_artifacts_one,
    aws_s3_bucket_public_access_block.secondary_artifacts_two
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

output "primary_artifact_bucket" {
  description = "S3 bucket used for primary artifacts."
  value       = aws_s3_bucket.primary_artifacts.bucket
}

output "secondary_artifact_bucket_one" {
  description = "S3 bucket used for secondary artifact one."
  value       = aws_s3_bucket.secondary_artifacts_one.bucket
}

output "secondary_artifact_bucket_two" {
  description = "S3 bucket used for secondary artifact two."
  value       = aws_s3_bucket.secondary_artifacts_two.bucket
}