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

resource "aws_s3_bucket" "a" {
  bucket = "a"
}

resource "aws_s3_bucket_logging" "a" {
  bucket = aws_s3_bucket.a.id

  target_bucket = "logging-680235478471"
  target_prefix = "log/"
}
