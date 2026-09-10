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

data "aws_iam_policy_document" "codebuild_s3_access" {
  statement {
    sid    = "WriteAutograderResults"
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]

    resources = [aws_s3_bucket.autograder_results.arn]
  }

  statement {
    sid    = "ManageAutograderResultObjects"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = ["${aws_s3_bucket.autograder_results.arn}/*"]
  }

  statement {
    sid    = "WriteCodeBuildLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_name}*"]
  }
}

resource "aws_s3_bucket" "autograder_results" {
  bucket_prefix = "cs-autograder-results-"
}

resource "aws_iam_role" "codebuild" {
  name_prefix        = "cs-autograder-codebuild-"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
}

resource "aws_iam_policy" "codebuild" {
  name_prefix = "cs-autograder-codebuild-"
  description = "Allows the CS autograder CodeBuild project to write results to S3 and logs to CloudWatch."
  policy      = data.aws_iam_policy_document.codebuild_s3_access.json
}

resource "aws_iam_role_policy_attachment" "codebuild" {
  role       = aws_iam_role.codebuild.name
  policy_arn = aws_iam_policy.codebuild.arn
}

resource "aws_codebuild_project" "autograder" {
  name         = var.project_name
  description  = "Runs CS class autograder jobs from GitHub and stores results in S3."
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.autograder_results.bucket
    name      = "autograder-results"
    packaging = "ZIP"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"
  }

  source {
    type      = "GITHUB"
    location  = var.github_repository_url
    buildspec = <<-EOT
      version: 0.2
      phases:
        build:
          commands:
            - echo "Run course autograder here"
            - mkdir -p results
            - echo "Autograder completed" > results/result.txt
      artifacts:
        files:
          - results/**/*
    EOT
  }
}
