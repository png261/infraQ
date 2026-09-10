terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the image storage bucket will be created."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name. A random suffix will be added to ensure global uniqueness."
  type        = string
  default     = "website-images"
}

variable "allowed_cors_origins" {
  description = "Origins allowed to access images from the bucket. Use your website domain in production."
  type        = list(string)
  default     = ["*"]
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "website_images" {
  bucket = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "Website Image Storage"
    Environment = "production"
    Purpose     = "Store images for website display"
  }
}

resource "aws_s3_bucket_ownership_controls" "website_images" {
  bucket = aws_s3_bucket.website_images.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "website_images" {
  bucket = aws_s3_bucket.website_images.id

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_versioning" "website_images" {
  bucket = aws_s3_bucket.website_images.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_cors_configuration" "website_images" {
  bucket = aws_s3_bucket.website_images.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = var.allowed_cors_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_policy" "public_read_images" {
  bucket = aws_s3_bucket.website_images.id

  depends_on = [
    aws_s3_bucket_public_access_block.website_images
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowPublicReadForWebsiteImages"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website_images.arn}/*"
      }
    ]
  })
}

output "image_bucket_name" {
  description = "Name of the S3 bucket used to store website images."
  value       = aws_s3_bucket.website_images.bucket
}

output "image_bucket_arn" {
  description = "ARN of the S3 bucket used to store website images."
  value       = aws_s3_bucket.website_images.arn
}

output "image_public_url_format" {
  description = "Public URL format for images uploaded to the bucket. Replace <image-file-name> with your uploaded object name."
  value       = "https://${aws_s3_bucket.website_images.bucket}.s3.${var.aws_region}.amazonaws.com/<image-file-name>"
}