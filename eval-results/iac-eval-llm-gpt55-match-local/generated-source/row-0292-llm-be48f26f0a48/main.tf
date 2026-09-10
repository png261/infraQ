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
  description = "AWS region where the S3 buckets will be created."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name_prefix" {
  description = "Prefix used for naming the S3 buckets."
  type        = string
  default     = "example-s3-logging"
}

data "aws_caller_identity" "current" {}

random_id "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "source" {
  bucket = "${var.bucket_name_prefix}-source-${random_id.suffix.hex}"
}

resource "aws_s3_bucket" "logs" {
  bucket = "${var.bucket_name_prefix}-logs-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3ServerAccessLogsPolicy"
        Effect = "Allow"

        Principal = {
          Service = "logging.s3.amazonaws.com"
        }

        Action = "s3:PutObject"

        Resource = "${aws_s3_bucket.logs.arn}/log/*"

        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.source.arn
          }
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.logs
  ]
}

resource "aws_s3_bucket_logging" "source_logging" {
  bucket        = aws_s3_bucket.source.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "log/"

  depends_on = [
    aws_s3_bucket_policy.logs
  ]
}

output "source_bucket_name" {
  description = "Name of the S3 bucket with server access logging enabled."
  value       = aws_s3_bucket.source.bucket
}

output "logs_bucket_name" {
  description = "Name of the S3 bucket where access logs are stored."
  value       = aws_s3_bucket.logs.bucket
}

output "log_object_prefix" {
  description = "Prefix used for S3 server access log objects."
  value       = "log/"
}