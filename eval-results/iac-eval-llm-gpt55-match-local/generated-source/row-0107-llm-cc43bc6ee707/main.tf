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

resource "aws_s3_bucket" "sample" {
  bucket = "sample"
}

resource "aws_s3_bucket_versioning" "sample" {
  bucket                = aws_s3_bucket.sample.id
  expected_bucket_owner = "123456789012"

  versioning_configuration {
    status = "Enabled"
  }
}