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
}

resource "aws_s3_bucket_metric" "entire_bucket_metrics" {
  bucket = aws_s3_bucket.mybucket.id
  name   = "EntireBucket"
}