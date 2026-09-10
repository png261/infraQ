terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "firehose_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream."
  type        = string
  default     = "new-relic-http-endpoint-firehose"
}

variable "http_endpoint_url" {
  description = "HTTP endpoint URL for the destination, such as New Relic."
  type        = string
  default     = "https://aws-api.newrelic.com/firehose/v1"
}

variable "http_endpoint_name" {
  description = "Name of the HTTP endpoint destination."
  type        = string
  default     = "New Relic"
}

variable "http_endpoint_access_key" {
  description = "Access key or license key for the HTTP endpoint destination."
  type        = string
  sensitive   = true
  default     = "REPLACE_WITH_NEW_RELIC_LICENSE_KEY"
}

variable "s3_backup_mode" {
  description = "Backup mode for the HTTP endpoint destination. Valid values are FailedDataOnly or AllData."
  type        = string
  default     = "FailedDataOnly"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "firehose_backup" {
  bucket = "firehose-http-endpoint-backup-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_ownership_controls" "firehose_backup" {
  bucket = aws_s3_bucket.firehose_backup.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "firehose_backup" {
  bucket = aws_s3_bucket.firehose_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "firehose_backup" {
  bucket = aws_s3_bucket.firehose_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${var.firehose_stream_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_stream" "firehose_s3_backup" {
  name           = "S3Backup"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_cloudwatch_log_stream" "firehose_http_endpoint" {
  name           = "HttpEndpointDelivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_iam_role" "firehose_role" {
  name = "firehose-http-endpoint-role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "firehose_policy" {
  name = "firehose-http-endpoint-policy-${random_id.suffix.hex}"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3BackupAccess"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.firehose_backup.arn,
          "${aws_s3_bucket.firehose_backup.arn}/*"
        ]
      },
      {
        Sid    = "AllowCloudWatchLogging"
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.firehose.arn}:log-stream:${aws_cloudwatch_log_stream.firehose_s3_backup.name}",
          "${aws_cloudwatch_log_group.firehose.arn}:log-stream:${aws_cloudwatch_log_stream.firehose_http_endpoint.name}"
        ]
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "http_endpoint_stream" {
  name        = var.firehose_stream_name
  destination = "http_endpoint"

  http_endpoint_configuration {
    url                = var.http_endpoint_url
    name               = var.http_endpoint_name
    access_key         = var.http_endpoint_access_key
    role_arn           = aws_iam_role.firehose_role.arn
    s3_backup_mode     = var.s3_backup_mode
    retry_duration     = 300

    buffering_size     = 5
    buffering_interval = 60

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_http_endpoint.name
    }

    request_configuration {
      content_encoding = "GZIP"

      common_attributes {
        name  = "source"
        value = "aws-kinesis-firehose"
      }

      common_attributes {
        name  = "destination"
        value = "new-relic"
      }
    }

    s3_configuration {
      role_arn           = aws_iam_role.firehose_role.arn
      bucket_arn         = aws_s3_bucket.firehose_backup.arn
      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"

      prefix              = "firehose-backup/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
      error_output_prefix = "firehose-errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"

      cloudwatch_logging_options {
        enabled         = true
        log_group_name  = aws_cloudwatch_log_group.firehose.name
        log_stream_name = aws_cloudwatch_log_stream.firehose_s3_backup.name
      }
    }
  }

  depends_on = [
    aws_iam_role_policy.firehose_policy,
    aws_s3_bucket_public_access_block.firehose_backup,
    aws_s3_bucket_server_side_encryption_configuration.firehose_backup
  ]
}

output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.http_endpoint_stream.name
}

output "firehose_delivery_stream_arn" {
  description = "ARN of the Kinesis Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.http_endpoint_stream.arn
}

output "s3_backup_bucket_name" {
  description = "Name of the S3 bucket used for Firehose backup data."
  value       = aws_s3_bucket.firehose_backup.bucket
}