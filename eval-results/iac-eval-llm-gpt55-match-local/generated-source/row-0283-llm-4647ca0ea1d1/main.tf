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
  description = "AWS region where the S3 bucket will be created."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name. A random suffix will be added."
  type        = string
  default     = "domain-com-cors-bucket"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "cors_bucket" {
  bucket = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "CORS Enabled S3 Bucket"
    Environment = "production"
  }
}

resource "aws_s3_bucket_ownership_controls" "cors_bucket" {
  bucket = aws_s3_bucket.cors_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "cors_bucket" {
  bucket = aws_s3_bucket.cors_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "cors_bucket" {
  bucket = aws_s3_bucket.cors_bucket.id

  cors_rule {
    allowed_methods = ["GET", "POST"]
    allowed_origins = ["https://domain.com"]
    allowed_headers = ["*"]
    expose_headers  = []
    max_age_seconds = 3000
  }
}

output "bucket_name" {
  description = "Name of the created S3 bucket."
  value       = aws_s3_bucket.cors_bucket.bucket
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket."
  value       = aws_s3_bucket.cors_bucket.arn
}