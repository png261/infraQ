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

variable "source_bucket_name_prefix" {
  description = "Prefix for the source S3 bucket name."
  type        = string
  default     = "weekly-inventory-source"
}

variable "inventory_bucket_name_prefix" {
  description = "Prefix for the destination S3 bucket that stores inventory reports."
  type        = string
  default     = "weekly-inventory-destination"
}

data "aws_caller_identity" "current" {}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "source" {
  bucket = "${var.source_bucket_name_prefix}-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket" "inventory_destination" {
  bucket = "${var.inventory_bucket_name_prefix}-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "inventory_destination" {
  bucket = aws_s3_bucket.inventory_destination.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "inventory_destination" {
  bucket = aws_s3_bucket.inventory_destination.id

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "inventory_destination" {
  bucket = aws_s3_bucket.inventory_destination.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "inventory_destination_policy" {
  statement {
    sid    = "AllowS3InventoryServiceToWriteReports"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.inventory_destination.arn}/inventory/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.source.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "inventory_destination" {
  bucket = aws_s3_bucket.inventory_destination.id
  policy = data.aws_iam_policy_document.inventory_destination_policy.json

  depends_on = [
    aws_s3_bucket_public_access_block.inventory_destination
  ]
}

resource "aws_s3_bucket_inventory" "weekly_current_versions_csv" {
  bucket = aws_s3_bucket.source.id
  name   = "weekly-current-object-versions-csv"

  included_object_versions = "Current"
  enabled                  = true

  schedule {
    frequency = "Weekly"
  }

  destination {
    bucket {
      account_id = data.aws_caller_identity.current.account_id
      bucket_arn = aws_s3_bucket.inventory_destination.arn
      format     = "CSV"
      prefix     = "inventory"
    }
  }

  optional_fields = [
    "Size",
    "LastModifiedDate",
    "StorageClass",
    "ETag",
    "IsMultipartUploaded",
    "ReplicationStatus",
    "EncryptionStatus",
    "ObjectLockRetainUntilDate",
    "ObjectLockRetentionMode",
    "ObjectLockLegalHoldStatus",
    "IntelligentTieringAccessTier",
    "BucketKeyStatus",
    "ChecksumAlgorithm"
  ]

  depends_on = [
    aws_s3_bucket_policy.inventory_destination,
    aws_s3_bucket_versioning.source,
    aws_s3_bucket_versioning.inventory_destination
  ]
}

output "source_bucket_name" {
  description = "Name of the source S3 bucket."
  value       = aws_s3_bucket.source.bucket
}

output "inventory_destination_bucket_name" {
  description = "Name of the S3 bucket where inventory reports are stored."
  value       = aws_s3_bucket.inventory_destination.bucket
}

output "inventory_report_prefix" {
  description = "Prefix in the destination bucket where inventory reports are written."
  value       = "inventory/"
}