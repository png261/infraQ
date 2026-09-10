terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the S3 buckets will be created."
  type        = string
  default     = "us-east-1"
}

variable "source_bucket_name_prefix" {
  description = "Prefix for the source S3 bucket name."
  type        = string
  default     = "private-source-bucket"
}

variable "logging_bucket_name_prefix" {
  description = "Prefix for the logging target S3 bucket name."
  type        = string
  default     = "log-delivery-target-bucket"
}

variable "log_file_prefix" {
  description = "Prefix to use for delivered S3 access logs."
  type        = string
  default     = "s3-access-logs/"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "source" {
  bucket = "${var.source_bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "Private Source Bucket"
    Environment = "demo"
  }
}

resource "aws_s3_bucket" "logging" {
  bucket = "${var.logging_bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "S3 Logging Target Bucket"
    Environment = "demo"
  }
}

resource "aws_s3_bucket_ownership_controls" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_ownership_controls" "logging" {
  bucket = aws_s3_bucket.logging.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "logging" {
  bucket = aws_s3_bucket.logging.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = false
  restrict_public_buckets = true
}

resource "aws_s3_bucket_acl" "source_private" {
  bucket = aws_s3_bucket.source.id
  acl    = "private"

  depends_on = [
    aws_s3_bucket_ownership_controls.source,
    aws_s3_bucket_public_access_block.source
  ]
}

resource "aws_s3_bucket_acl" "logging_log_delivery_write" {
  bucket = aws_s3_bucket.logging.id
  acl    = "log-delivery-write"

  depends_on = [
    aws_s3_bucket_ownership_controls.logging,
    aws_s3_bucket_public_access_block.logging
  ]
}

resource "aws_s3_bucket_logging" "source_to_logging_bucket" {
  bucket = aws_s3_bucket.source.id

  target_bucket = aws_s3_bucket.logging.id
  target_prefix = var.log_file_prefix

  depends_on = [
    aws_s3_bucket_acl.source_private,
    aws_s3_bucket_acl.logging_log_delivery_write
  ]
}

output "source_bucket_name" {
  description = "Name of the private source S3 bucket."
  value       = aws_s3_bucket.source.id
}

output "logging_bucket_name" {
  description = "Name of the S3 bucket receiving access logs."
  value       = aws_s3_bucket.logging.id
}

output "log_prefix" {
  description = "Prefix used for S3 access log files."
  value       = var.log_file_prefix
}