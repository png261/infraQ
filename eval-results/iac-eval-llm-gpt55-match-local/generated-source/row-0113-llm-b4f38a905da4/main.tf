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

resource "aws_s3_bucket" "pike_bucket" {
  bucket = "pike-680235478471"
}

resource "aws_s3_bucket_request_payment_configuration" "pike_bucket_request_payment" {
  bucket = aws_s3_bucket.pike_bucket.id
  payer  = "Requester"
}