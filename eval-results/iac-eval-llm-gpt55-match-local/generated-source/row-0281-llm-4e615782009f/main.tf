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

variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name. A random suffix will be added."
  type        = string
  default     = "kms-encrypted-bucket"
}

data "aws_caller_identity" "current" {}

random_id "bucket_suffix" {
  byte_length = 4
}

resource "aws_kms_key" "s3_kms_key" {
  description             = "Customer-managed KMS key for S3 server-side encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "s3-kms-key-policy"
    Statement = [
      {
        Sid    = "AllowRootAccountFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowS3UseOfKey"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "s3-bucket-encryption-key"
    Environment = "example"
  }
}

resource "aws_kms_alias" "s3_kms_key_alias" {
  name          = "alias/s3-bucket-encryption-key"
  target_key_id = aws_kms_key.s3_kms_key.key_id
}

resource "aws_s3_bucket" "encrypted_bucket" {
  bucket = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "kms-encrypted-s3-bucket"
    Environment = "example"
  }
}

resource "aws_s3_bucket_public_access_block" "encrypted_bucket_public_access_block" {
  bucket = aws_s3_bucket.encrypted_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encrypted_bucket_sse" {
  bucket = aws_s3_bucket.encrypted_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_kms_key.arn
      sse_algorithm     = "aws:kms"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "encrypted_bucket_versioning" {
  bucket = aws_s3_bucket.encrypted_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

output "s3_bucket_name" {
  description = "Name of the created S3 bucket."
  value       = aws_s3_bucket.encrypted_bucket.bucket
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for S3 encryption."
  value       = aws_kms_key.s3_kms_key.arn
}