terraform {
  required_version = ">= 1.3.0"

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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "delivery_stream_name" {
  description = "Name of the Kinesis Firehose Delivery Stream."
  type        = string
  default     = "example-extended-s3-firehose"
}

variable "s3_prefix" {
  description = "S3 prefix for delivered Firehose records."
  type        = string
  default     = "firehose-data/"
}

variable "s3_error_output_prefix" {
  description = "S3 prefix for Firehose delivery errors."
  type        = string
  default     = "firehose-errors/"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "firehose_destination" {
  bucket        = "firehose-destination-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "firehose_destination" {
  bucket = aws_s3_bucket.firehose_destination.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "firehose_destination" {
  bucket = aws_s3_bucket.firehose_destination.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "firehose_role" {
  name = "firehose-extended-s3-role-${random_id.suffix.hex}"

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

resource "aws_iam_policy" "firehose_s3_policy" {
  name        = "firehose-extended-s3-policy-${random_id.suffix.hex}"
  description = "Allows Kinesis Firehose to deliver records to the destination S3 bucket."

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

resource "aws_iam_role_policy_attachment" "firehose_s3_policy_attachment" {
  role       = aws_iam_role.firehose_role.name
  policy_arn = aws_iam_policy.firehose_s3_policy.arn
}

resource "aws_kinesis_firehose_delivery_stream" "extended_s3_stream" {
  name        = var.delivery_stream_name
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose_role.arn
    bucket_arn          = aws_s3_bucket.firehose_destination.arn
    prefix              = var.s3_prefix
    error_output_prefix = var.s3_error_output_prefix

    buffering_size     = 5
    buffering_interval = 300

    compression_format = "GZIP"

    processing_configuration {
      enabled = false
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.firehose_s3_policy_attachment,
    aws_s3_bucket_public_access_block.firehose_destination,
    aws_s3_bucket_versioning.firehose_destination
  ]
}

output "firehose_delivery_stream_name" {
  description = "Name of the created Kinesis Firehose Delivery Stream."
  value       = aws_kinesis_firehose_delivery_stream.extended_s3_stream.name
}

output "firehose_delivery_stream_arn" {
  description = "ARN of the created Kinesis Firehose Delivery Stream."
  value       = aws_kinesis_firehose_delivery_stream.extended_s3_stream.arn
}

output "destination_s3_bucket_name" {
  description = "Name of the destination S3 bucket."
  value       = aws_s3_bucket.firehose_destination.bucket
}