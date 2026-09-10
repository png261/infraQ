resource "aws_s3_bucket" "codebuild_artifacts" {
  bucket_prefix = "iac-eval-codebuild-artifacts-"
}

resource "aws_iam_role" "codebuild" {
  name_prefix = "iac-eval-codebuild-"

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

resource "aws_codebuild_project" "example" {
  name         = "iac-eval-github-build"
  description  = "Example CodeBuild project using GitHub source, S3 artifacts, and S3 cache."
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.codebuild_artifacts.bucket
    packaging = "ZIP"
  }

  cache {
    type     = "S3"
    location = aws_s3_bucket.codebuild_artifacts.bucket
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "GITHUB"
    location  = "https://github.com/aws-samples/aws-codebuild-samples.git"
    buildspec = <<-BUILDSPEC
      version: 0.2

      phases:
        build:
          commands:
            - echo "IaC Eval example build"
      artifacts:
        files:
          - '**/*'
    BUILDSPEC
  }
}
