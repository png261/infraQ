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
  default     = "bucket-owner-pays"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "bucket_owner_pays" {
  bucket = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "Bucket Owner Pays S3 Bucket"
    Environment = "default"
  }
}

resource "aws_s3_bucket_ownership_controls" "bucket_owner_pays" {
  bucket = aws_s3_bucket.bucket_owner_pays.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "bucket_owner_pays" {
  bucket = aws_s3_bucket.bucket_owner_pays.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_request_payment_configuration" "bucket_owner_pays" {
  bucket = aws_s3_bucket.bucket_owner_pays.id
  payer  = "BucketOwner"
}

output "bucket_name" {
  description = "Name of the created S3 bucket."
  value       = aws_s3_bucket.bucket_owner_pays.bucket
}

output "request_payment_payer" {
  description = "Indicates who pays for S3 request and data transfer fees."
  value       = aws_s3_bucket_request_payment_configuration.bucket_owner_pays.payer
}