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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "kms_key_description" {
  description = "Description for the KMS key used to encrypt the S3 bucket."
  type        = string
  default     = "Customer managed KMS key for S3 bucket server-side encryption"
}

variable "kms_deletion_window_in_days" {
  description = "Number of days before the KMS key is deleted after destruction."
  type        = number
  default     = 7
}

variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name. A random suffix will be added for global uniqueness."
  type        = string
  default     = "kms-encrypted-s3-bucket"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_kms_key" "s3_kms_key" {
  description             = var.kms_key_description
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true

  tags = {
    Name        = "s3-kms-encryption-key"
    Environment = "example"
  }
}

resource "aws_s3_bucket" "encrypted_bucket" {
  bucket = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"
    Environment = "example"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encrypted_bucket_sse" {
  bucket = aws_s3_bucket.encrypted_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_kms_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}