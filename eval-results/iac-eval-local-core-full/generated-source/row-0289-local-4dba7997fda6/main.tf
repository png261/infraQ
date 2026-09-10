terraform {
  required_version = ">= 1.6.0"

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

resource "aws_s3_bucket" "benchmark" {
  bucket_prefix = "iac-eval-bucket-owner-pays-"
}

resource "aws_s3_bucket_request_payment_configuration" "benchmark" {
  bucket = aws_s3_bucket.benchmark.id
  payer  = "BucketOwner"
}
