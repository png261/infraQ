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
  description = "AWS region where the S3 bucket will be created."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name. A random suffix will be added."
  type        = string
  default     = "example-payment-config-bucket"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "example" {
  bucket = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "Example S3 Bucket with Payment Configuration"
    Environment = "Example"
  }
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.example.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_request_payment_configuration" "example" {
  bucket = aws_s3_bucket.example.id
  payer  = "Requester"
}

output "bucket_name" {
  description = "Name of the created S3 bucket."
  value       = aws_s3_bucket.example.bucket
}

output "request_payment_payer" {
  description = "The request payment configuration payer setting."
  value       = aws_s3_bucket_request_payment_configuration.example.payer
}