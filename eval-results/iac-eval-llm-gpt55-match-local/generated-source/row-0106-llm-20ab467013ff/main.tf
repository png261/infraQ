terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "test_bucket" {
  bucket        = "test-bucket"
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "test-bucket"
    Environment = "default"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_ownership_controls" "test_bucket" {
  bucket = aws_s3_bucket.test_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "test_bucket" {
  bucket = aws_s3_bucket.test_bucket.id
  acl    = "private"

  depends_on = [
    aws_s3_bucket_ownership_controls.test_bucket,
    aws_s3_bucket_public_access_block.test_bucket
  ]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "test_bucket" {
  bucket = aws_s3_bucket.test_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }

    bucket_key_enabled = false
  }
}

resource "aws_s3_bucket_public_access_block" "test_bucket" {
  bucket = aws_s3_bucket.test_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}