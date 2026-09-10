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

variable "project_name" {
  description = "Name prefix for the autograder infrastructure."
  type        = string
  default     = "cs-autograder"
}

variable "github_repository_url" {
  description = "GitHub repository URL containing the autograder source/buildspec."
  type        = string
  default     = "https://github.com/example/cs-autograder.git"
}

variable "codebuild_image" {
  description = "CodeBuild managed image used to run student submissions."
  type        = string
  default     = "aws/codebuild/standard:7.0"
}

resource "aws_s3_bucket" "autograder_results" {
  bucket_prefix = "${var.project_name}-results-"
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

resource "aws_iam_role" "codebuild" {
  name_prefix        = "${var.project_name}-codebuild-"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    sid    = "WriteAutograderResults"
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]

    resources = [aws_s3_bucket.autograder_results.arn]
  }

  statement {
    sid    = "ManageAutograderResultObjects"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:GetObjectVersion"
    ]

    resources = ["${aws_s3_bucket.autograder_results.arn}/*"]
  }

  statement {
    sid    = "WriteCodeBuildLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "codebuild" {
  name_prefix = "${var.project_name}-codebuild-"
  description = "Permissions for CodeBuild to write autograder artifacts and logs."
  policy      = data.aws_iam_policy_document.codebuild.json
}

resource "aws_iam_role_policy_attachment" "codebuild" {
  role       = aws_iam_role.codebuild.name
  policy_arn = aws_iam_policy.codebuild.arn
}

resource "aws_codebuild_project" "autograder" {
  name         = var.project_name
  description  = "Runs CS autograder jobs from GitHub and stores results in S3."
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.autograder_results.bucket
    name      = "autograder-results"
    packaging = "ZIP"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = var.codebuild_image
    type         = "LINUX_CONTAINER"
  }

  source {
    type      = "GITHUB"
    location  = var.github_repository_url
    buildspec = "buildspec.yml"
  }
}

output "results_bucket_name" {
  description = "S3 bucket where CodeBuild stores autograder results."
  value       = aws_s3_bucket.autograder_results.bucket
}

output "codebuild_project_name" {
  description = "CodeBuild project name for the autograder."
  value       = aws_codebuild_project.autograder.name
}
