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

resource "aws_s3_bucket" "codebuild_output" {
  bucket        = "students-codebuild-output-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "codebuild_output" {
  bucket = aws_s3_bucket.codebuild_output.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "codebuild_output" {
  bucket = aws_s3_bucket.codebuild_output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "codebuild_output" {
  bucket = aws_s3_bucket.codebuild_output.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "codebuild_service_role" {
  name = "students-codebuild-service-role-${random_id.suffix.hex}"

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
  name = "students-codebuild-service-policy-${random_id.suffix.hex}"
  role = aws_iam_role.codebuild_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.codebuild_output.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.codebuild_output.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_codebuild_project" "students_codebuild_project" {
  name          = "students-codebuild-project-${random_id.suffix.hex}"
  description   = "CodeBuild project for building students' code and storing output artifacts in S3."
  service_role  = aws_iam_role.codebuild_service_role.arn
  build_timeout = 30

  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.codebuild_output.bucket
    packaging = "ZIP"
    path      = "codebuild-output"
    name      = "students-build-output"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "alpine"
    type         = "LINUX_CONTAINER"
  }

  source {
    type            = "GITHUB"
    git_clone_depth = 1
    location        = "https://github.com/source-location"
  }

  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }
  }

  depends_on = [
    aws_iam_role_policy.codebuild_service_policy,
    aws_s3_bucket_public_access_block.codebuild_output,
    aws_s3_bucket_ownership_controls.codebuild_output
  ]
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket used for CodeBuild output artifacts."
  value       = aws_s3_bucket.codebuild_output.bucket
}

output "codebuild_project_name" {
  description = "Name of the AWS CodeBuild project."
  value       = aws_codebuild_project.students_codebuild_project.name
}