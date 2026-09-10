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
  description = "AWS region where the resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "firehose_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream."
  type        = string
  default     = "splunk-firehose-delivery-stream"
}

variable "splunk_hec_endpoint" {
  description = "Splunk HTTP Event Collector endpoint."
  type        = string
  default     = "https://http-inputs.example.splunkcloud.com:443"
}

variable "splunk_hec_token" {
  description = "Splunk HTTP Event Collector token."
  type        = string
  sensitive   = true
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "splunk_hec_endpoint_type" {
  description = "Splunk HEC endpoint type. Valid values are Raw or Event."
  type        = string
  default     = "Event"
}

variable "backup_s3_prefix" {
  description = "S3 prefix for failed Splunk delivery records."
  type        = string
  default     = "splunk-failed-records/"
}

variable "backup_s3_error_prefix" {
  description = "S3 prefix for Firehose delivery errors."
  type        = string
  default     = "splunk-errors/"
}

resource "aws_s3_bucket" "firehose_backup" {
  bucket_prefix = "firehose-splunk-backup-"

  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "firehose_backup" {
  bucket = aws_s3_bucket.firehose_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${var.firehose_stream_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_stream" "firehose" {
  name           = "SplunkDelivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_iam_role" "firehose_role" {
  name = "${var.firehose_stream_name}-role"

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

resource "aws_iam_policy" "firehose_policy" {
  name        = "${var.firehose_stream_name}-policy"
  description = "IAM policy allowing Firehose to write backup records to S3 and logs to CloudWatch."

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
          "${aws_cloudwatch_log_group.firehose.arn}:log-stream:${aws_cloudwatch_log_stream.firehose.name}"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "firehose_policy_attachment" {
  role       = aws_iam_role.firehose_role.name
  policy_arn = aws_iam_policy.firehose_policy.arn
}

resource "aws_kinesis_firehose_delivery_stream" "splunk" {
  name        = var.firehose_stream_name
  destination = "splunk"

  splunk_configuration {
    hec_endpoint               = var.splunk_hec_endpoint
    hec_token                  = var.splunk_hec_token
    hec_endpoint_type          = var.splunk_hec_endpoint_type
    hec_acknowledgment_timeout = 180
    retry_duration             = 300
    s3_backup_mode             = "FailedEventsOnly"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose.name
    }

    s3_configuration {
      role_arn           = aws_iam_role.firehose_role.arn
      bucket_arn         = aws_s3_bucket.firehose_backup.arn
      prefix             = var.backup_s3_prefix
      error_output_prefix = var.backup_s3_error_prefix

      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"

      cloudwatch_logging_options {
        enabled         = true
        log_group_name  = aws_cloudwatch_log_group.firehose.name
        log_stream_name = aws_cloudwatch_log_stream.firehose.name
      }
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.firehose_policy_attachment,
    aws_s3_bucket_public_access_block.firehose_backup
  ]
}

output "firehose_delivery_stream_name" {
  description = "Name of the created Kinesis Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.splunk.name
}

output "firehose_delivery_stream_arn" {
  description = "ARN of the created Kinesis Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.splunk.arn
}

output "backup_s3_bucket_name" {
  description = "Name of the S3 bucket used for failed delivery backup."
  value       = aws_s3_bucket.firehose_backup.bucket
}