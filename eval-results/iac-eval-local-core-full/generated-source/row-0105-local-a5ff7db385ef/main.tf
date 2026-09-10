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

resource "aws_s3_bucket" "my_bucket" {
  bucket        = "my-bucket"
  force_destroy = true
}

resource "aws_s3_bucket_metric" "my_bucket_metric" {
  bucket = aws_s3_bucket.my_bucket.id
  name   = "my_bucket_metric"
}

resource "aws_s3_bucket_object" "my_object" {
  bucket  = aws_s3_bucket.my_bucket.id
  key     = "my_object"
  content = "This is the content stored in my_object."
}
