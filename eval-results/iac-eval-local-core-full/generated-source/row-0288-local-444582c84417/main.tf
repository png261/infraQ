provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "example" {
  bucket_prefix = "iac-eval-request-payment-"
}

resource "aws_s3_bucket_request_payment_configuration" "example" {
  bucket = aws_s3_bucket.example.id
  payer  = "BucketOwner"
}
