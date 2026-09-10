terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    local = {
      source  = "hashicorp/local"
      version = ">= 2.4"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "your_bucket_name" {
  bucket = "your-bucket-name-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_ownership_controls" "your_bucket_name" {
  bucket = aws_s3_bucket.your_bucket_name.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "your_bucket_name" {
  bucket = aws_s3_bucket.your_bucket_name.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "local_file" "source_file" {
  filename = "path/to/file"
  content  = "object"
}

resource "aws_s3_object" "object" {
  bucket = aws_s3_bucket.your_bucket_name.id
  key    = "new_object_key"
  source = local_file.source_file.filename

  etag = filemd5(local_file.source_file.filename)

  depends_on = [
    aws_s3_bucket_ownership_controls.your_bucket_name,
    aws_s3_bucket_public_access_block.your_bucket_name
  ]
}