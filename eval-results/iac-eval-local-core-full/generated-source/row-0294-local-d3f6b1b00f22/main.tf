terraform {
  required_version = ">= 1.5.0"

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

data "aws_iam_policy_document" "autograder_codebuild_permissions" {
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
    sid    = "ManageAutograderArtifacts"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject"
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

resource "aws_s3_bucket" "autograder_results" {
  bucket        = var.results_bucket_name
  force_destroy = true
}

resource "aws_iam_role" "codebuild_autograder" {
  name               = "${var.project_name}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
}

resource "aws_iam_policy" "codebuild_autograder" {
  name        = "${var.project_name}-codebuild-policy"
  description = "Allows the autograder CodeBuild project to write logs and store grading results."
  policy      = data.aws_iam_policy_document.autograder_codebuild_permissions.json
}

resource "aws_iam_role_policy_attachment" "codebuild_autograder" {
  role       = aws_iam_role.codebuild_autograder.name
  policy_arn = aws_iam_policy.codebuild_autograder.arn
}

resource "aws_codebuild_project" "autograder" {
  name         = var.project_name
  description  = "CS class autograder that runs student code from GitHub and stores results in S3."
  service_role = aws_iam_role.codebuild_autograder.arn

  artifacts {
    type     = "S3"
    location = aws_s3_bucket.autograder_results.bucket
    name     = "autograder-results"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"
  }

  source {
    type      = "GITHUB"
    location  = var.github_repository_url
    buildspec = "buildspec.yml"
  }
}
