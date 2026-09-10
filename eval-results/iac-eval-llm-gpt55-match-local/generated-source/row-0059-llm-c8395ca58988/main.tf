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

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "dynamic-partition-firehose"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "firehose_destination" {
  bucket = "${var.project_name}-bucket-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_public_access_block" "firehose_destination" {
  bucket = aws_s3_bucket.firehose_destination.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "firehose_destination" {
  bucket = aws_s3_bucket.firehose_destination.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role" "firehose_role" {
  name = "${var.project_name}-role-${random_id.suffix.hex}"

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

resource "aws_iam_role_policy" "firehose_s3_policy" {
  name = "${var.project_name}-s3-policy"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
          aws_s3_bucket.firehose_destination.arn,
          "${aws_s3_bucket.firehose_destination.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "extended_s3_dynamic_partitioning" {
  name        = "${var.project_name}-stream-${random_id.suffix.hex}"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.firehose_destination.arn

    buffering_size     = 64
    buffering_interval = 300
    compression_format = "GZIP"

    prefix = "data/customer_id=!{partitionKeyFromQuery:customer_id}/event_type=!{partitionKeyFromQuery:event_type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"

    error_output_prefix = "errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"

    dynamic_partitioning_configuration {
      enabled = true

      retry_duration = 300
    }

    processing_configuration {
      enabled = true

      processors {
        type = "MetadataExtraction"

        parameters {
          parameter_name  = "MetadataExtractionQuery"
          parameter_value = "{customer_id:.customer_id,event_type:.event_type}"
        }

        parameters {
          parameter_name  = "JsonParsingEngine"
          parameter_value = "JQ-1.6"
        }
      }

      processors {
        type = "AppendDelimiterToRecord"

        parameters {
          parameter_name  = "Delimiter"
          parameter_value = "\\n"
        }
      }
    }
  }

  depends_on = [
    aws_iam_role_policy.firehose_s3_policy,
    aws_s3_bucket_public_access_block.firehose_destination,
    aws_s3_bucket_server_side_encryption_configuration.firehose_destination
  ]
}

output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.extended_s3_dynamic_partitioning.name
}

output "s3_bucket_name" {
  description = "Name of the destination S3 bucket."
  value       = aws_s3_bucket.firehose_destination.bucket
}