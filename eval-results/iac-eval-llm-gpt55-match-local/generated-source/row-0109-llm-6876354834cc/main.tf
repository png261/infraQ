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
  region = "eu-west-1"
}

resource "aws_s3_bucket" "platform_infra" {
  bucket        = "wellcomecollection-platform-infra"
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "wellcomecollection-platform-infra"
    ManagedBy   = "Terraform"
    Environment = "Platform"
  }
}

resource "aws_s3_bucket_public_access_block" "platform_infra" {
  bucket = aws_s3_bucket.platform_infra.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "platform_infra" {
  bucket = aws_s3_bucket.platform_infra.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "platform_infra" {
  bucket = aws_s3_bucket.platform_infra.id
  acl    = "private"

  depends_on = [
    aws_s3_bucket_ownership_controls.platform_infra,
    aws_s3_bucket_public_access_block.platform_infra
  ]
}

resource "aws_s3_bucket_versioning" "platform_infra" {
  bucket = aws_s3_bucket.platform_infra.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "platform_infra" {
  bucket = aws_s3_bucket.platform_infra.id

  rule {
    id     = "delete-tmp-objects-after-30-days"
    status = "Enabled"

    filter {
      prefix = "tmp/"
    }

    expiration {
      days = 30
    }
  }

  rule {
    id     = "manage-noncurrent-object-versions"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.platform_infra
  ]
}