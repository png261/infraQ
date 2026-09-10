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

resource "aws_s3_bucket" "this" {
  bucket = "mybucket"
}

resource "aws_s3_object" "file" {
  bucket = aws_s3_bucket.this.id
  key    = "file"
  source = "path/to/file"
}
