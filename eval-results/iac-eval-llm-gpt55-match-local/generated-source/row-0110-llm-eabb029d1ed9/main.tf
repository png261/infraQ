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
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "source_bucket_name" {
  description = "Name of the source S3 bucket. S3 bucket names must be globally unique and at least 3 characters."
  type        = string
  default     = "a-680235478471"
}

variable "logging_bucket_name" {
  description = "Name of the target S3 bucket for access logs."
  type        = string
  default     = "logging-680235478471"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "a" {
  bucket = var.source_bucket_name
}

resource "aws_s3_bucket" "logging" {
  bucket = var.logging_bucket_name
}

resource "aws_s3_bucket_public_access_block" "a" {
  bucket = aws_s3_bucket.a.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "logging" {
  bucket = aws_s3_bucket.logging.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logging" {
  bucket = aws_s3_bucket.logging.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "logging" {
  bucket = aws_s3_bucket.logging.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3ServerAccessLogs"
        Effect = "Allow"

        Principal = {
          Service = "logging.s3.amazonaws.com"
        }

        Action = "s3:PutObject"

        Resource = "${aws_s3_bucket.logging.arn}/log/*"

        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.a.arn
          }

          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_logging" "a" {
  bucket = aws_s3_bucket.a.id

  target_bucket = aws_s3_bucket.logging.id
  target_prefix = "log/"

  depends_on = [
    aws_s3_bucket_policy.logging
  ]
}

output "source_bucket_name" {
  value = aws_s3_bucket.a.bucket
}

output "logging_bucket_name" {
  value = aws_s3_bucket.logging.bucket
}

output "logging_prefix" {
  value = "log/"
}