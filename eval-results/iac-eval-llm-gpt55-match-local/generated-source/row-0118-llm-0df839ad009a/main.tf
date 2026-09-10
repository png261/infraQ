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

resource "aws_s3_bucket" "mybucket" {
  bucket = "mybucket"

  object_lock_enabled = true
}

resource "aws_s3_bucket_versioning" "mybucket_versioning" {
  bucket = aws_s3_bucket.mybucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "mybucket_object_lock" {
  bucket = aws_s3_bucket.mybucket.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 5
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.mybucket_versioning
  ]
}

output "bucket_id" {
  value = aws_s3_bucket.mybucket.id
}

output "bucket_arn" {
  value = aws_s3_bucket.mybucket.arn
}