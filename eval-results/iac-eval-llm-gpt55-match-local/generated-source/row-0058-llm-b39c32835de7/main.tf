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

provider "random" {}

variable "aws_region" {
  description = "AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "application_name" {
  description = "Name of the Amazon Kinesis Analytics V2 Apache Flink application."
  type        = string
  default     = "basic-flink-analytics-app"
}

variable "runtime_environment" {
  description = "Apache Flink runtime environment for Kinesis Analytics V2."
  type        = string
  default     = "FLINK-1_15"
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days."
  type        = number
  default     = 14
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  bucket_name        = "flink-app-artifacts-${random_id.suffix.hex}"
  flink_artifact_key = "artifacts/basic-flink-placeholder.zip"
}

resource "aws_s3_bucket" "flink_artifacts" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_ownership_controls" "flink_artifacts" {
  bucket = aws_s3_bucket.flink_artifacts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "flink_artifacts" {
  bucket = aws_s3_bucket.flink_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "flink_artifacts" {
  bucket = aws_s3_bucket.flink_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "flink_placeholder_zip" {
  bucket = aws_s3_bucket.flink_artifacts.id
  key    = local.flink_artifact_key

  /*
    This is a minimal empty ZIP file encoded in base64.
    Replace this object with a real Apache Flink application JAR or ZIP artifact
    before starting the application for production use.
  */
  content_base64 = "UEsFBgAAAAAAAAAAAAAAAAAAAAAAAA=="

  content_type = "application/zip"

  depends_on = [
    aws_s3_bucket_versioning.flink_artifacts
  ]
}

resource "aws_cloudwatch_log_group" "flink" {
  name              = "/aws/kinesis-analytics/${var.application_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_stream" "flink" {
  name           = "application"
  log_group_name = aws_cloudwatch_log_group.flink.name
}

data "aws_iam_policy_document" "kinesis_analytics_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["kinesisanalytics.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "flink_execution_role" {
  name               = "${var.application_name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.kinesis_analytics_assume_role.json
}

data "aws_iam_policy_document" "flink_execution_policy" {
  statement {
    sid    = "AllowReadFlinkArtifacts"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion"
    ]

    resources = [
      aws_s3_object.flink_placeholder_zip.arn
    ]
  }

  statement {
    sid    = "AllowListArtifactBucket"
    effect = "Allow"

    actions = [
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.flink_artifacts.arn
    ]
  }

  statement {
    sid    = "AllowCloudWatchLogging"
    effect = "Allow"

    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      aws_cloudwatch_log_group.flink.arn,
      "${aws_cloudwatch_log_group.flink.arn}:*"
    ]
  }

  statement {
    sid    = "AllowCloudWatchMetrics"
    effect = "Allow"

    actions = [
      "cloudwatch:PutMetricData"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "flink_execution_policy" {
  name   = "${var.application_name}-execution-policy"
  role   = aws_iam_role.flink_execution_role.id
  policy = data.aws_iam_policy_document.flink_execution_policy.json
}

resource "aws_kinesisanalyticsv2_application" "flink" {
  name                   = var.application_name
  runtime_environment    = var.runtime_environment
  service_execution_role = aws_iam_role.flink_execution_role.arn
  application_mode       = "STREAMING"

  application_configuration {
    application_code_configuration {
      code_content_type = "ZIPFILE"

      code_content {
        s3_content_location {
          bucket_arn     = aws_s3_bucket.flink_artifacts.arn
          file_key       = aws_s3_object.flink_placeholder_zip.key
          object_version = aws_s3_object.flink_placeholder_zip.version_id
        }
      }
    }

    flink_application_configuration {
      checkpoint_configuration {
        configuration_type             = "CUSTOM"
        checkpointing_enabled          = true
        checkpoint_interval            = 60000
        min_pause_between_checkpoints  = 5000
      }

      monitoring_configuration {
        configuration_type = "CUSTOM"
        log_level          = "INFO"
        metrics_level      = "APPLICATION"
      }

      parallelism_configuration {
        configuration_type   = "CUSTOM"
        parallelism          = 1
        parallelism_per_kpu  = 1
        auto_scaling_enabled = true
      }
    }

    environment_properties {
      property_group {
        property_group_id = "FlinkApplicationProperties"

        property_map = {
          ApplicationName = var.application_name
          Environment     = "dev"
        }
      }
    }
  }

  depends_on = [
    aws_iam_role_policy.flink_execution_policy,
    aws_s3_object.flink_placeholder_zip
  ]
}

resource "aws_kinesisanalyticsv2_application_cloudwatch_logging_option" "flink" {
  application_name = aws_kinesisanalyticsv2_application.flink.name

  cloudwatch_logging_option {
    log_stream_arn = aws_cloudwatch_log_stream.flink.arn
  }

  depends_on = [
    aws_kinesisanalyticsv2_application.flink
  ]
}

output "kinesis_analytics_application_name" {
  description = "Name of the Kinesis Analytics V2 Apache Flink application."
  value       = aws_kinesisanalyticsv2_application.flink.name
}

output "kinesis_analytics_application_arn" {
  description = "ARN of the Kinesis Analytics V2 Apache Flink application."
  value       = aws_kinesisanalyticsv2_application.flink.arn
}

output "flink_artifact_bucket_name" {
  description = "S3 bucket containing the Flink application artifact."
  value       = aws_s3_bucket.flink_artifacts.bucket
}

output "flink_artifact_s3_key" {
  description = "S3 key of the uploaded Flink placeholder artifact."
  value       = aws_s3_object.flink_placeholder_zip.key
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group used by the Flink application."
  value       = aws_cloudwatch_log_group.flink.name
}