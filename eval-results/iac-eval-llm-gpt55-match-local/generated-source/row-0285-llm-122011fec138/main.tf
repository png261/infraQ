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
  description = "AWS region where the S3 bucket will be created."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name. A random suffix will be added for global uniqueness."
  type        = string
  default     = "static-website-bucket"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "static_website" {
  bucket = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "Static Website Bucket"
    Environment = "Demo"
  }
}

resource "aws_s3_bucket_ownership_controls" "static_website" {
  bucket = aws_s3_bucket.static_website.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "static_website" {
  bucket = aws_s3_bucket.static_website.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "static_website" {
  bucket = aws_s3_bucket.static_website.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.static_website.id
  key          = "index.html"
  content_type = "text/html"

  content = <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>Static Website on S3</title>
</head>
<body>
  <h1>Hello from Amazon S3!</h1>
  <p>This static website is hosted using Terraform.</p>
</body>
</html>
EOF
}

data "aws_iam_policy_document" "public_read" {
  statement {
    sid    = "PublicReadGetObject"
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.static_website.arn}/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.static_website.id
  policy = data.aws_iam_policy_document.public_read.json

  depends_on = [
    aws_s3_bucket_public_access_block.static_website
  ]
}

output "bucket_name" {
  description = "Name of the S3 bucket."
  value       = aws_s3_bucket.static_website.bucket
}

output "website_endpoint" {
  description = "S3 static website endpoint."
  value       = aws_s3_bucket_website_configuration.static_website.website_endpoint
}

output "website_url" {
  description = "HTTP URL for the hosted static website."
  value       = "http://${aws_s3_bucket_website_configuration.static_website.website_endpoint}"
}