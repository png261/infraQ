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
  description = "AWS region where the autograder infrastructure will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "github_repository_url" {
  description = "GitHub repository URL containing student submissions or autograder target code."
  type        = string
  default     = "https://github.com/example-org/example-student-repo.git"
}

variable "github_branch" {
  description = "GitHub branch to build and grade."
  type        = string
  default     = "main"
}

variable "codebuild_project_name" {
  description = "Name of the AWS CodeBuild project."
  type        = string
  default     = "cs-class-autograder"
}

variable "autograder_results_prefix" {
  description = "S3 prefix where grading results will be stored."
  type        = string
  default     = "results"
}

variable "build_compute_type" {
  description = "CodeBuild compute type."
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
}

variable "build_image" {
  description = "CodeBuild Docker image used as the grading environment."
  type        = string
  default     = "aws/codebuild/standard:7.0"
}

variable "build_timeout_minutes" {
  description = "Maximum time in minutes for each autograder build."
  type        = number
  default     = 30
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "autograder_results" {
  bucket = "cs-autograder-results-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "CS Autograder Results"
    Environment = "education"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_ownership_controls" "autograder_results" {
  bucket = aws_s3_bucket.autograder_results.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "autograder_results" {
  bucket = aws_s3_bucket.autograder_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "autograder_results" {
  bucket = aws_s3_bucket.autograder_results.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "autograder_results" {
  bucket = aws_s3_bucket.autograder_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudwatch_log_group" "codebuild_logs" {
  name              = "/aws/codebuild/${var.codebuild_project_name}"
  retention_in_days = 30

  tags = {
    Name        = "CS Autograder CodeBuild Logs"
    Environment = "education"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role" "codebuild_service_role" {
  name = "${var.codebuild_project_name}-service-role"

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

  tags = {
    Name        = "CS Autograder CodeBuild Service Role"
    Environment = "education"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "${var.codebuild_project_name}-policy"
  role = aws_iam_role.codebuild_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_group.codebuild_logs.arn,
          "${aws_cloudwatch_log_group.codebuild_logs.arn}:*"
        ]
      },
      {
        Sid    = "S3ResultsBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.autograder_results.arn
      },
      {
        Sid    = "S3ResultsObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.autograder_results.arn}/*"
      }
    ]
  })
}

resource "aws_codebuild_project" "autograder" {
  name          = var.codebuild_project_name
  description   = "Autograder for a CS class. Pulls student code from GitHub, runs tests, and stores results in S3."
  service_role  = aws_iam_role.codebuild_service_role.arn
  build_timeout = var.build_timeout_minutes

  source {
    type            = "GITHUB"
    location        = var.github_repository_url
    git_clone_depth = 1
    buildspec       = <<-EOT
      version: 0.2

      env:
        shell: bash

      phases:
        install:
          runtime-versions:
            python: 3.11
          commands:
            - echo "Installing autograder dependencies..."
            - python --version
            - pip install --upgrade pip
            - |
              if [ -f requirements.txt ]; then
                pip install -r requirements.txt
              fi

        pre_build:
          commands:
            - echo "Preparing grading workspace..."
            - mkdir -p autograder-output
            - echo "Repository: $CODEBUILD_SOURCE_REPO_URL" > autograder-output/metadata.txt
            - echo "Commit: $CODEBUILD_RESOLVED_SOURCE_VERSION" >> autograder-output/metadata.txt
            - echo "Build ID: $CODEBUILD_BUILD_ID" >> autograder-output/metadata.txt
            - echo "Started at: $(date -u)" >> autograder-output/metadata.txt

        build:
          commands:
            - echo "Running autograder..."
            - |
              set +e

              if [ -x ./run_tests.sh ]; then
                ./run_tests.sh > autograder-output/test-output.txt 2>&1
                TEST_EXIT_CODE=$?
              elif [ -f ./run_tests.sh ]; then
                bash ./run_tests.sh > autograder-output/test-output.txt 2>&1
                TEST_EXIT_CODE=$?
              elif [ -f ./pytest.ini ] || find . -maxdepth 3 -name "test_*.py" | grep -q .; then
                pip install pytest
                pytest -q > autograder-output/test-output.txt 2>&1
                TEST_EXIT_CODE=$?
              else
                echo "No supported test runner found. Provide run_tests.sh or pytest tests." > autograder-output/test-output.txt
                TEST_EXIT_CODE=2
              fi

              echo "$TEST_EXIT_CODE" > autograder-output/exit-code.txt

              if [ "$TEST_EXIT_CODE" -eq 0 ]; then
                echo '{"status":"passed"}' > autograder-output/result.json
              else
                echo '{"status":"failed"}' > autograder-output/result.json
              fi

              exit 0

        post_build:
          commands:
            - echo "Uploading grading result to S3..."
            - RESULT_PATH="${AUTOGRADER_RESULTS_PREFIX}/${CODEBUILD_BUILD_ID}"
            - aws s3 cp autograder-output "s3://${RESULTS_BUCKET}/${RESULT_PATH}/" --recursive
            - echo "Results uploaded to s3://${RESULTS_BUCKET}/${RESULT_PATH}/"

      artifacts:
        files:
          - autograder-output/**/*
        discard-paths: no
    EOT
  }

  source_version = var.github_branch

  environment {
    compute_type                = var.build_compute_type
    image                       = var.build_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "RESULTS_BUCKET"
      value = aws_s3_bucket.autograder_results.bucket
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "AUTOGRADER_RESULTS_PREFIX"
      value = var.autograder_results_prefix
      type  = "PLAINTEXT"
    }
  }

  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.autograder_results.bucket
    path      = "artifacts"
    namespace_type = "BUILD_ID"
    packaging = "NONE"
  }

  logs_config {
    cloudwatch_logs {
      status      = "ENABLED"
      group_name  = aws_cloudwatch_log_group.codebuild_logs.name
      stream_name = "autograder"
    }

    s3_logs {
      status   = "ENABLED"
      location = "${aws_s3_bucket.autograder_results.id}/logs"
    }
  }

  tags = {
    Name        = "CS Class Autograder"
    Environment = "education"
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_iam_role_policy.codebuild_policy,
    aws_s3_bucket_public_access_block.autograder_results,
    aws_s3_bucket_server_side_encryption_configuration.autograder_results
  ]
}

output "results_bucket_name" {
  description = "S3 bucket where autograder results and artifacts are stored."
  value       = aws_s3_bucket.autograder_results.bucket
}

output "results_bucket_arn" {
  description = "ARN of the S3 bucket used by the autograder."
  value       = aws_s3_bucket.autograder_results.arn
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild autograder project."
  value       = aws_codebuild_project.autograder.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild autograder project."
  value       = aws_codebuild_project.autograder.arn
}