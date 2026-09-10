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
  description = "Prefix for the S3 bucket name. A random suffix is added to ensure global uniqueness."
  type        = string
  default     = "terraformai-managed-s3-bucket"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "managed_bucket" {
  bucket = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "TerraformAI Managed S3 Bucket"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_ownership_controls" "managed_bucket_ownership" {
  bucket = aws_s3_bucket.managed_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "managed_bucket_acl" {
  bucket = aws_s3_bucket.managed_bucket.id
  acl    = "private"

  depends_on = [
    aws_s3_bucket_ownership_controls.managed_bucket_ownership
  ]
}