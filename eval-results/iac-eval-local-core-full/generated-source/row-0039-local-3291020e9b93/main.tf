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

resource "aws_iam_role" "codebuild" {
  name               = "example-codebuild-role-${data.aws_caller_identity.current.account_id}"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
}

resource "aws_s3_bucket" "primary_artifacts" {
  bucket        = "example-codebuild-primary-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket" "secondary_artifacts" {
  bucket        = "example-codebuild-secondary-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

data "aws_iam_policy_document" "codebuild_artifacts" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetBucketAcl",
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.primary_artifacts.arn,
      aws_s3_bucket.secondary_artifacts.arn,
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.primary_artifacts.arn}/*",
      "${aws_s3_bucket.secondary_artifacts.arn}/*",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codebuild_artifacts" {
  name   = "example-codebuild-artifacts"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild_artifacts.json
}

resource "aws_codebuild_project" "example" {
  name         = "example-secondary-artifacts-build"
  description  = "Example CodeBuild project with primary and secondary S3 artifacts."
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type     = "S3"
    location = aws_s3_bucket.primary_artifacts.bucket
    name     = "primary-output"
  }

  secondary_artifacts {
    artifact_identifier = "secondary_output"
    type                = "S3"
    location            = aws_s3_bucket.secondary_artifacts.bucket
    name                = "secondary-output"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "NO_SOURCE"
    buildspec = <<-EOT
      version: 0.2
      phases:
        build:
          commands:
            - echo "Hello from CodeBuild"
            - echo "primary artifact" > primary.txt
            - echo "secondary artifact" > secondary.txt
      artifacts:
        files:
          - primary.txt
        secondary-artifacts:
          secondary_output:
            files:
              - secondary.txt
    EOT
  }
}
