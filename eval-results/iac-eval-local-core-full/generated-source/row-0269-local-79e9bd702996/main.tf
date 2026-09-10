terraform {
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

resource "aws_s3_bucket" "this" {
  bucket = "mybucket"
}

resource "aws_s3_bucket_accelerate_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  status = "Enabled"
}
