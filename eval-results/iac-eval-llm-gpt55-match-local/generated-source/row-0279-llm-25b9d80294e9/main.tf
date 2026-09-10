terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "locked_bucket" {
  bucket              = "mybucket"
  object_lock_enabled = true
}

resource "aws_s3_bucket_versioning" "locked_bucket_versioning" {
  bucket = aws_s3_bucket.locked_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "locked_bucket_object_lock" {
  bucket = aws_s3_bucket.locked_bucket.id

  object_lock_enabled = "Enabled"

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 30
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.locked_bucket_versioning
  ]
}