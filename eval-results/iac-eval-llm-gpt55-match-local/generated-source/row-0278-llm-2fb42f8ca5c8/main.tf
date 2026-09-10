terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the S3 bucket will be created."
  type        = string
  default     = "us-east-1"
}

variable "pdf_file_path" {
  description = "Local path to the PDF file to upload."
  type        = string
  default     = "assets/test.pdf"
}

variable "pdf_object_key" {
  description = "The object key to use for the uploaded PDF in S3."
  type        = string
  default     = "test.pdf"
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

resource "aws_s3_bucket" "pdf_storage" {
  bucket = "pdf-storage-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "PDF Storage Bucket"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "pdf_storage" {
  bucket = aws_s3_bucket.pdf_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pdf_storage" {
  bucket = aws_s3_bucket.pdf_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "pdf_file" {
  bucket       = aws_s3_bucket.pdf_storage.id
  key          = var.pdf_object_key
  source       = var.pdf_file_path
  content_type = "application/pdf"

  etag = filemd5(var.pdf_file_path)

  depends_on = [
    aws_s3_bucket_public_access_block.pdf_storage,
    aws_s3_bucket_server_side_encryption_configuration.pdf_storage
  ]

  tags = {
    Name      = "Uploaded PDF"
    ManagedBy = "terraform"
  }
}

output "bucket_name" {
  description = "Name of the S3 bucket storing the PDF."
  value       = aws_s3_bucket.pdf_storage.bucket
}

output "pdf_s3_uri" {
  description = "S3 URI of the uploaded PDF file."
  value       = "s3://${aws_s3_bucket.pdf_storage.bucket}/${aws_s3_object.pdf_file.key}"
}