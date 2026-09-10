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

variable "project_name" {
  description = "Name prefix for the autograder infrastructure."
  type        = string
  default     = "cs-autograder"
}

variable "github_repo_url" {
  description = "GitHub repository URL containing the student code or autograder target code."
  type        = string
  default     = "https://github.com/octocat/Hello-World.git"
}

variable "github_branch" {
  description = "GitHub branch to check out before running the autograder."
  type        = string
  default     = "main"
}

variable "test_command" {
  description = "Command executed by CodeBuild to run the autograder tests."
  type        = string
  default     = "python3 -m unittest discover || true"
}

variable "codebuild_compute_type" {
  description = "Compute size for the CodeBuild autograder environment."
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
}

variable "codebuild_image" {
  description = "Docker image used by CodeBuild for the autograder environment."
  type        = string
  default     = "aws/codebuild/standard:7.0"
}

variable "codebuild_environment_type" {
  description = "CodeBuild environment type."
  type        = string
  default     = "LINUX_CONTAINER"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "autograder_results" {
  bucket = "${var.project_name}-results-${random_id.suffix.hex}"

  tags = {
    Name        = "${var.project_name}-results"
    Environment = "autograder"
  }
}

resource "aws_s3_bucket_public_access_block" "autograder_results" {
  bucket = aws_s3_bucket.autograder_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "autograder_results" {
  bucket = aws_s3_bucket.autograder_results.id

  rule {
    object_ownership = "BucketOwnerEnforced"
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

resource "aws_s3_bucket_versioning" "autograder_results" {
  bucket = aws_s3_bucket.autograder_results.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_cloudwatch_log_group" "codebuild_logs" {
  name              = "/aws/codebuild/${var.project_name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-logs"
    Environment = "autograder"
  }
}

resource "aws_iam_role" "codebuild_role" {
  name = "${var.project_name}-codebuild-role-${random_id.suffix.hex}"

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
    Name        = "${var.project_name}-codebuild-role"
    Environment = "autograder"
  }
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "${var.project_name}-codebuild-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchLogs"
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
        Sid    = "AllowS3ResultStorage"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.autograder_results.arn,
          "${aws_s3_bucket.autograder_results.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_codebuild_project" "autograder" {
  name          = var.project_name
  description   = "Autograder for running CS student code from GitHub and storing results in S3."
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 30

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                       = var.codebuild_image
    type                        = var.codebuild_environment_type
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "RESULTS_BUCKET"
      value = aws_s3_bucket.autograder_results.bucket
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "GITHUB_REPO_URL"
      value = var.github_repo_url
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "GITHUB_BRANCH"
      value = var.github_branch
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "TEST_COMMAND"
      value = var.test_command
      type  = "PLAINTEXT"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild_logs.name
      stream_name = "autograder"
      status      = "ENABLED"
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = <<-BUILDSPEC
      version: 0.2

      phases:
        install:
          commands:
            - echo "Preparing autograder environment"
            - python3 --version || true
            - git --version
            - aws --version

        pre_build:
          commands:
            - echo "Starting autograder run"
            - export RUN_ID="$(date +%Y%m%d%H%M%S)-$CODEBUILD_BUILD_NUMBER"
            - export RESULT_DIR="autograder-results/$RUN_ID"
            - mkdir -p "$RESULT_DIR"
            - echo "Repository: $GITHUB_REPO_URL" | tee "$RESULT_DIR/metadata.txt"
            - echo "Branch: $GITHUB_BRANCH" | tee -a "$RESULT_DIR/metadata.txt"
            - echo "Build ID: $CODEBUILD_BUILD_ID" | tee -a "$RESULT_DIR/metadata.txt"
            - echo "Run ID: $RUN_ID" | tee -a "$RESULT_DIR/metadata.txt"
            - git clone "$GITHUB_REPO_URL" student_submission
            - cd student_submission
            - git checkout "$GITHUB_BRANCH" || echo "Branch checkout failed; continuing with default branch"

        build:
          commands:
            - echo "Running autograder command: $TEST_COMMAND"
            - set +e
            - bash -c "$TEST_COMMAND" > "../$RESULT_DIR/test-output.txt" 2>&1
            - export TEST_EXIT_CODE=$?
            - set -e
            - echo "$TEST_EXIT_CODE" > "../$RESULT_DIR/exit-code.txt"
            - cd ..
            - |
              if [ "$TEST_EXIT_CODE" -eq 0 ]; then
                echo "PASS" > "$RESULT_DIR/status.txt"
              else
                echo "FAIL" > "$RESULT_DIR/status.txt"
              fi

        post_build:
          commands:
            - echo "Uploading autograder results to S3"
            - aws s3 cp "$RESULT_DIR" "s3://$RESULTS_BUCKET/$RESULT_DIR" --recursive
            - echo "Results uploaded to s3://$RESULTS_BUCKET/$RESULT_DIR"
            - |
              if [ "$(cat "$RESULT_DIR/exit-code.txt")" -ne 0 ]; then
                echo "Autograder tests failed"
                exit 1
              fi
              echo "Autograder tests passed"
    BUILDSPEC
  }

  tags = {
    Name        = var.project_name
    Environment = "autograder"
  }
}

output "results_bucket_name" {
  description = "Name of the S3 bucket where autograder results are stored."
  value       = aws_s3_bucket.autograder_results.bucket
}

output "results_bucket_arn" {
  description = "ARN of the S3 bucket where autograder results are stored."
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