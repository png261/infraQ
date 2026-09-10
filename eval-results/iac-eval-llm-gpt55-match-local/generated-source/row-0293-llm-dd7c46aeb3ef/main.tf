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
  description = "Prefix used to create globally unique S3 bucket names."
  type        = string
  default     = "terraform-s3-access-logs"
}

resource "random_id" "suffix" {
  byte_length = 4
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "source" {
  bucket = "${var.bucket_name_prefix}-source-${random_id.suffix.hex}"

  tags = {
    Name        = "Source S3 Bucket"
    Environment = "demo"
    Purpose     = "Stores application data"
  }
}

resource "aws_s3_bucket" "logs" {
  bucket = "${var.bucket_name_prefix}-logs-${random_id.suffix.hex}"

  tags = {
    Name        = "S3 Access Logs Bucket"
    Environment = "demo"
    Purpose     = "Stores server access logs"
  }
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
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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

resource "aws_s3_bucket_ownership_controls" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

data "aws_iam_policy_document" "logs_bucket_policy" {
  statement {
    sid    = "AllowS3ServerAccessLogsWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.logs.arn}/source-bucket-access-logs/*"
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
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs_bucket_policy.json
}

resource "aws_s3_bucket_logging" "source" {
  bucket = aws_s3_bucket.source.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "source-bucket-access-logs/"

  depends_on = [
    aws_s3_bucket_policy.logs,
    aws_s3_bucket_public_access_block.source,
    aws_s3_bucket_public_access_block.logs,
    aws_s3_bucket_ownership_controls.source,
    aws_s3_bucket_ownership_controls.logs
  ]
}

output "source_bucket_name" {
  description = "Name of the primary S3 bucket."
  value       = aws_s3_bucket.source.bucket
}

output "logs_bucket_name" {
  description = "Name of the S3 bucket storing server access logs."
  value       = aws_s3_bucket.logs.bucket
}

output "log_prefix" {
  description = "Prefix in the logging bucket where S3 server access logs are stored."
  value       = "source-bucket-access-logs/"
}