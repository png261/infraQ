terraform {
  required_version = ">= 1.0"

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

resource "aws_s3_bucket" "pike_bucket" {
  bucket = "pike-680235478471"
}

resource "aws_s3_bucket_public_access_block" "pike_bucket_public_access_block" {
  bucket = aws_s3_bucket.pike_bucket.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}