data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  artifact_bucket_name = coalesce(var.artifact_bucket_name, "codebuild-batch-artifacts-${data.aws_caller_identity.current.account_id}")
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = local.artifact_bucket_name
  force_destroy = true
}

resource "aws_iam_role" "codebuild" {
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

  inline_policy {
    name = "example-codebuild-batch-access"

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
          Resource = "arn:${data.aws_partition.current.partition}:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/example-batch-project*"
        },
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:GetObjectVersion",
            "s3:PutObject"
          ]
          Resource = "${aws_s3_bucket.artifacts.arn}/*"
        },
        {
          Effect   = "Allow"
          Action   = "s3:ListBucket"
          Resource = aws_s3_bucket.artifacts.arn
        }
      ]
    })
  }
}

resource "aws_codebuild_project" "example" {
  name          = "example-batch-project"
  description   = "Example CodeBuild project with build batch configuration."
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  artifacts {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket
    path     = "artifacts"
    name     = "example-batch-project"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "NO_SOURCE"
    buildspec = <<-EOT
      version: 0.2
      batch:
        fast-fail: false
        build-list:
          - identifier: example_build
            buildspec: |
              version: 0.2
              phases:
                build:
                  commands:
                    - echo "Hello from CodeBuild batch"
    EOT
  }

  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }
  }

  build_batch_config {
    service_role = aws_iam_role.codebuild.arn

    restrictions {
      maximum_builds_allowed = 2
    }
  }
}
