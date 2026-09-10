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
  description = "Name of the CodeBuild autograder project."
  type        = string
  default     = "cs-class-autograder"
}

variable "github_repository_url" {
  description = "GitHub repository URL containing the student code or grading harness."
  type        = string
  default     = "https://github.com/octocat/Hello-World.git"
}

variable "github_branch" {
  description = "GitHub branch to build and grade."
  type        = string
  default     = "main"
}

variable "build_compute_type" {
  description = "CodeBuild compute type."
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
}

variable "build_image" {
  description = "CodeBuild Docker image used as the controlled grading environment."
  type        = string
  default     = "aws/codebuild/standard:7.0"
}

variable "build_timeout_minutes" {
  description = "Maximum build time in minutes."
  type        = number
  default     = 20
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "autograder_results" {
  bucket = "${var.project_name}-results-${random_id.suffix.hex}"

  tags = {
    Name        = "${var.project_name}-results"
    Environment = "classroom"
    Purpose     = "autograder-results"
  }
}

resource "aws_s3_bucket_public_access_block" "autograder_results" {
  bucket = aws_s3_bucket.autograder_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${var.project_name}"
  retention_in_days = 30

  tags = {
    Name        = "/aws/codebuild/${var.project_name}"
    Environment = "classroom"
    Purpose     = "autograder-logs"
  }
}

resource "aws_iam_role" "codebuild_service_role" {
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
    Environment = "classroom"
    Purpose     = "autograder"
  }
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "${var.project_name}-codebuild-policy"
  role = aws_iam_role.codebuild_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_group.codebuild.arn,
          "${aws_cloudwatch_log_group.codebuild.arn}:*"
        ]
      },
      {
        Sid    = "AllowS3ResultsAccess"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.autograder_results.arn
      },
      {
        Sid    = "AllowS3ResultsObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.autograder_results.arn}/*"
      },
      {
        Sid    = "AllowCodeBuildReports"
        Effect = "Allow"
        Action = [
          "codebuild:CreateReportGroup",
          "codebuild:CreateReport",
          "codebuild:UpdateReport",
          "codebuild:BatchPutTestCases",
          "codebuild:BatchPutCodeCoverages"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_codebuild_project" "autograder" {
  name          = var.project_name
  description   = "AWS CodeBuild autograder for running CS student submissions from GitHub and storing grading results."
  service_role  = aws_iam_role.codebuild_service_role.arn
  build_timeout = var.build_timeout_minutes

  source_version = var.github_branch

  source {
    type            = "GITHUB"
    location        = var.github_repository_url
    git_clone_depth = 1

    buildspec = <<-YAML
      version: 0.2

      env:
        shell: bash

      phases:
        install:
          runtime-versions:
            python: 3.11
          commands:
            - echo "Preparing controlled autograder environment"
            - python --version
            - mkdir -p autograder-results

        pre_build:
          commands:
            - echo "Starting autograder run"
            - echo "Repository: $CODEBUILD_SOURCE_REPO_URL"
            - echo "Commit: $CODEBUILD_RESOLVED_SOURCE_VERSION"
            - echo "Build ID: $CODEBUILD_BUILD_ID"

        build:
          commands:
            - |
              set +e

              START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
              SCORE=0
              STATUS="failed"
              DETAILS="No grading command was found."

              if [ -f "./grade.sh" ]; then
                echo "Found grade.sh; running grading script."
                chmod +x ./grade.sh
                ./grade.sh > autograder-results/grade-output.txt 2>&1
                EXIT_CODE=$?
                if [ "$EXIT_CODE" -eq 0 ]; then
                  SCORE=100
                  STATUS="passed"
                  DETAILS="grade.sh completed successfully."
                else
                  SCORE=0
                  STATUS="failed"
                  DETAILS="grade.sh exited with status $EXIT_CODE."
                fi
              elif [ -f "./pytest.ini" ] || [ -d "./tests" ]; then
                echo "Found Python test configuration or tests directory; running pytest."
                pip install pytest > autograder-results/install-output.txt 2>&1
                pytest -q > autograder-results/grade-output.txt 2>&1
                EXIT_CODE=$?
                if [ "$EXIT_CODE" -eq 0 ]; then
                  SCORE=100
                  STATUS="passed"
                  DETAILS="pytest completed successfully."
                else
                  SCORE=0
                  STATUS="failed"
                  DETAILS="pytest exited with status $EXIT_CODE."
                fi
              else
                echo "No grade.sh, pytest.ini, or tests directory found." > autograder-results/grade-output.txt
                EXIT_CODE=1
              fi

              END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

              cat > autograder-results/result.json <<EOF
              {
                "project": "${var.project_name}",
                "repository": "$CODEBUILD_SOURCE_REPO_URL",
                "commit": "$CODEBUILD_RESOLVED_SOURCE_VERSION",
                "build_id": "$CODEBUILD_BUILD_ID",
                "status": "$STATUS",
                "score": $SCORE,
                "details": "$DETAILS",
                "started_at": "$START_TIME",
                "finished_at": "$END_TIME"
              }
              EOF

              cat autograder-results/result.json

              exit 0

        post_build:
          commands:
            - echo "Autograder finished. Results will be uploaded to S3 as CodeBuild artifacts."

      artifacts:
        files:
          - autograder-results/**/*
        discard-paths: no

      reports:
        autograder-report:
          files:
            - autograder-results/result.json
          file-format: RAW
    YAML
  }

  artifacts {
    type                = "S3"
    location            = aws_s3_bucket.autograder_results.bucket
    path                = "codebuild-artifacts"
    namespace_type      = "BUILD_ID"
    name                = "autograder-results"
    packaging           = "ZIP"
    override_artifact_name = false
    encryption_disabled = false
  }

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
      name  = "PROJECT_NAME"
      value = var.project_name
      type  = "PLAINTEXT"
    }
  }

  logs_config {
    cloudwatch_logs {
      status      = "ENABLED"
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "autograder"
    }

    s3_logs {
      status              = "ENABLED"
      location            = "${aws_s3_bucket.autograder_results.id}/codebuild-logs"
      encryption_disabled = false
    }
  }

  tags = {
    Name        = var.project_name
    Environment = "classroom"
    Purpose     = "cs-autograder"
  }
}

resource "aws_codebuild_webhook" "autograder" {
  project_name = aws_codebuild_project.autograder.name
  build_type   = "BUILD"

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH,PULL_REQUEST_CREATED,PULL_REQUEST_UPDATED"
    }

    filter {
      type    = "HEAD_REF"
      pattern = "refs/heads/${var.github_branch}"
    }
  }
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild autograder project."
  value       = aws_codebuild_project.autograder.name
}

output "results_bucket_name" {
  description = "S3 bucket where autograder results and logs are stored."
  value       = aws_s3_bucket.autograder_results.bucket
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group for autograder build logs."
  value       = aws_cloudwatch_log_group.codebuild.name
}

output "start_build_command" {
  description = "AWS CLI command to manually start an autograder build."
  value       = "aws codebuild start-build --project-name ${aws_codebuild_project.autograder.name} --region ${var.aws_region}"
}