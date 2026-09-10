terraform {
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

resource "aws_s3_bucket" "pdf_storage" {
  bucket_prefix = "iac-eval-pdf-"
}

resource "aws_s3_object" "test_pdf" {
  bucket = aws_s3_bucket.pdf_storage.id
  key    = "test.pdf"
  source = "assets/test.pdf"
}
