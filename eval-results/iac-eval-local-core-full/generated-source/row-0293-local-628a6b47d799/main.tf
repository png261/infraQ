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

resource "aws_s3_bucket" "source" {
  bucket_prefix = "iac-eval-source-"
}

resource "aws_s3_bucket" "access_logs" {
  bucket_prefix = "iac-eval-logs-"
}

resource "aws_s3_bucket_logging" "source" {
  bucket        = aws_s3_bucket.source.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "log/"
}
