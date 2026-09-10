resource "aws_iam_role" "codebuild" {
  name = "example-codebuild-service-role"

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

resource "aws_s3_bucket" "codebuild_cache" {
  bucket_prefix = "example-codebuild-cache-"
}

resource "aws_codebuild_project" "example" {
  name          = "example-github-codebuild-project"
  description   = "Example CodeBuild project using a GitHub source, environment variables, and S3 cache."
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 10

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "EXAMPLE_ENV"
      value = "example-value"
      type  = "PLAINTEXT"
    }
  }

  source {
    type      = "GITHUB"
    location  = "https://github.com/aws-samples/aws-codebuild-samples.git"
    buildspec = <<-EOT
      version: 0.2

      phases:
        build:
          commands:
            - echo "Hello from CodeBuild"
    EOT
  }

  cache {
    type     = "S3"
    location = aws_s3_bucket.codebuild_cache.bucket
  }
}
