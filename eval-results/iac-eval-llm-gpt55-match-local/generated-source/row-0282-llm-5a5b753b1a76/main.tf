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
  description = "Prefix for the S3 bucket name. A random suffix will be appended."
  type        = string
  default     = "example-cors-bucket"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "example" {
  bucket = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_cors_configuration" "example" {
  bucket = aws_s3_bucket.example.id

  cors_rule {
    id = "example-cors-rule"

    allowed_methods = [
      "GET",
      "PUT",
      "POST",
      "DELETE",
      "HEAD"
    ]

    allowed_origins = [
      "https://example.com"
    ]

    allowed_headers = [
      "*"
    ]

    expose_headers = [
      "ETag",
      "x-amz-request-id"
    ]

    max_age_seconds = 3000
  }
}

output "bucket_name" {
  description = "Name of the created S3 bucket."
  value       = aws_s3_bucket.example.bucket
}

output "cors_configuration_id" {
  description = "ID of the S3 bucket CORS configuration."
  value       = aws_s3_bucket_cors_configuration.example.id
}