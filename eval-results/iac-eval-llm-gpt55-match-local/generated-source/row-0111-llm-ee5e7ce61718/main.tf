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

resource "aws_s3_bucket" "example_bucket" {
  bucket              = "example-bucket"
  object_lock_enabled = true

  tags = {
    Name        = "example-bucket"
    Environment = "example"
  }
}

resource "aws_s3_bucket_versioning" "example_bucket_versioning" {
  bucket = aws_s3_bucket.example_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "example_bucket_object_lock" {
  bucket = aws_s3_bucket.example_bucket.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 90
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.example_bucket_versioning
  ]
}