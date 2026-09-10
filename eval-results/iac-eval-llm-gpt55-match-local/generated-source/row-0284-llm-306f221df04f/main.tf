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

variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name. A random suffix will be added."
  type        = string
  default     = "example-static-website"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "website_bucket" {
  bucket = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "Example Static Website Bucket"
    Environment = "Example"
  }
}

resource "aws_s3_bucket_ownership_controls" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.website_bucket.id
  key          = "index.html"
  content_type = "text/html"

  content = <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>Example S3 Website</title>
</head>
<body>
  <h1>Hello from S3 Static Website Hosting</h1>
  <p>This page is served from an S3 bucket configured with Terraform.</p>
</body>
</html>
EOF
}

resource "aws_s3_object" "error_html" {
  bucket       = aws_s3_bucket.website_bucket.id
  key          = "error.html"
  content_type = "text/html"

  content = <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>Error</title>
</head>
<body>
  <h1>Something went wrong</h1>
  <p>The requested page could not be found.</p>
</body>
</html>
EOF
}

resource "aws_s3_bucket_policy" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id

  depends_on = [
    aws_s3_bucket_public_access_block.website_bucket
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website_bucket.arn}/*"
      }
    ]
  })
}

output "bucket_name" {
  description = "Name of the created S3 bucket."
  value       = aws_s3_bucket.website_bucket.id
}

output "website_endpoint" {
  description = "S3 static website endpoint."
  value       = aws_s3_bucket_website_configuration.website_bucket.website_endpoint
}

output "website_domain" {
  description = "S3 static website domain."
  value       = aws_s3_bucket_website_configuration.website_bucket.website_domain
}