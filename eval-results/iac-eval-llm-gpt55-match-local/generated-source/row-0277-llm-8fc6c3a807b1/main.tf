terraform {
  required_version = ">= 1.0.0"

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

resource "aws_s3_bucket" "mybucket" {
  bucket = "mybucket"
}

resource "aws_s3_object" "uploaded_file" {
  bucket = aws_s3_bucket.mybucket.id
  key    = "file"
  source = "path/to/file"

  etag = filemd5("path/to/file")
}