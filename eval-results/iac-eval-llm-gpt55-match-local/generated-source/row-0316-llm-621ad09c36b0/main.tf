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
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the S3 bucket will be created."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "global-video-streaming"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "prod"
}

variable "price_class" {
  description = "CloudFront price class. Use PriceClass_All for global distribution."
  type        = string
  default     = "PriceClass_All"
}

variable "cloudfront_default_root_object" {
  description = "Default root object for the CloudFront distribution."
  type        = string
  default     = "index.html"
}

locals {
  bucket_name = "${var.project_name}-${var.environment}-${data.aws_caller_identity.current.account_id}"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "video_bucket" {
  bucket = local.bucket_name

  tags = {
    Name        = local.bucket_name
    Project     = var.project_name
    Environment = var.environment
    Purpose     = "Video content origin for CloudFront"
  }
}

resource "aws_s3_bucket_ownership_controls" "video_bucket" {
  bucket = aws_s3_bucket.video_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "video_bucket" {
  bucket = aws_s3_bucket.video_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "video_bucket" {
  bucket = aws_s3_bucket.video_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "video_bucket" {
  bucket = aws_s3_bucket.video_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "video_bucket" {
  bucket = aws_s3_bucket.video_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag", "Content-Length", "Content-Range"]
    max_age_seconds = 3000
  }
}

resource "aws_cloudfront_origin_access_control" "video_oac" {
  name                              = "${var.project_name}-${var.environment}-oac"
  description                       = "Origin Access Control for private S3 video bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_response_headers_policy" "video_cors_policy" {
  name    = "${var.project_name}-${var.environment}-cors-policy"
  comment = "CORS response headers policy for video streaming"

  cors_config {
    access_control_allow_credentials = false

    access_control_allow_headers {
      items = ["*"]
    }

    access_control_allow_methods {
      items = ["GET", "HEAD", "OPTIONS"]
    }

    access_control_allow_origins {
      items = ["*"]
    }

    access_control_expose_headers {
      items = ["ETag", "Content-Length", "Content-Range"]
    }

    access_control_max_age_sec = 3000
    origin_override            = true
  }
}

resource "aws_cloudfront_distribution" "video_distribution" {
  enabled             = true
  comment             = "Global CloudFront distribution for video streaming content"
  default_root_object = var.cloudfront_default_root_object
  price_class         = var.price_class
  http_version        = "http2and3"
  is_ipv6_enabled     = true

  origin {
    domain_name              = aws_s3_bucket.video_bucket.bucket_regional_domain_name
    origin_id                = "s3-video-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.video_oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-video-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    compress = true

    cache_policy_id            = aws_cloudfront_cache_policy.video_cache_policy.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.video_origin_request_policy.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.video_cors_policy.id
  }

  ordered_cache_behavior {
    path_pattern           = "*.mp4"
    target_origin_id       = "s3-video-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    compress = false

    cache_policy_id            = aws_cloudfront_cache_policy.video_cache_policy.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.video_origin_request_policy.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.video_cors_policy.id
  }

  ordered_cache_behavior {
    path_pattern           = "*.m3u8"
    target_origin_id       = "s3-video-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    compress = true

    cache_policy_id            = aws_cloudfront_cache_policy.hls_manifest_cache_policy.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.video_origin_request_policy.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.video_cors_policy.id
  }

  ordered_cache_behavior {
    path_pattern           = "*.ts"
    target_origin_id       = "s3-video-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    compress = false

    cache_policy_id            = aws_cloudfront_cache_policy.video_cache_policy.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.video_origin_request_policy.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.video_cors_policy.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-distribution"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudfront_cache_policy" "video_cache_policy" {
  name        = "${var.project_name}-${var.environment}-video-cache-policy"
  comment     = "Long-lived cache policy for video objects"
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = false
    enable_accept_encoding_gzip   = false

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "whitelist"

      headers {
        items = ["Origin", "Access-Control-Request-Headers", "Access-Control-Request-Method", "Range"]
      }
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_cache_policy" "hls_manifest_cache_policy" {
  name        = "${var.project_name}-${var.environment}-hls-manifest-cache-policy"
  comment     = "Shorter cache policy for HLS manifest files"
  default_ttl = 60
  max_ttl     = 300
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "whitelist"

      headers {
        items = ["Origin", "Access-Control-Request-Headers", "Access-Control-Request-Method"]
      }
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_origin_request_policy" "video_origin_request_policy" {
  name    = "${var.project_name}-${var.environment}-origin-request-policy"
  comment = "Forward headers required for CORS and byte-range video requests"

  cookies_config {
    cookie_behavior = "none"
  }

  headers_config {
    header_behavior = "whitelist"

    headers {
      items = [
        "Origin",
        "Access-Control-Request-Headers",
        "Access-Control-Request-Method",
        "Range"
      ]
    }
  }

  query_strings_config {
    query_string_behavior = "none"
  }
}

data "aws_iam_policy_document" "video_bucket_policy" {
  statement {
    sid    = "AllowCloudFrontServicePrincipalReadOnly"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.video_bucket.arn}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"

      values = [
        aws_cloudfront_distribution.video_distribution.arn
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "video_bucket_policy" {
  bucket = aws_s3_bucket.video_bucket.id
  policy = data.aws_iam_policy_document.video_bucket_policy.json

  depends_on = [
    aws_s3_bucket_public_access_block.video_bucket,
    aws_cloudfront_distribution.video_distribution
  ]
}

resource "aws_s3_object" "sample_index" {
  bucket       = aws_s3_bucket.video_bucket.id
  key          = "index.html"
  content_type = "text/html"

  content = <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>Global Video Streaming</title>
</head>
<body>
  <h1>Global Video Streaming Site</h1>
  <p>Upload video files such as MP4 or HLS assets to this private S3 bucket.</p>
  <p>Serve them globally using the CloudFront distribution domain.</p>
</body>
</html>
EOF
}

output "s3_bucket_name" {
  description = "Private S3 bucket used as the video origin."
  value       = aws_s3_bucket.video_bucket.bucket
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket."
  value       = aws_s3_bucket.video_bucket.bucket_regional_domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  value       = aws_cloudfront_distribution.video_distribution.id
}

output "cloudfront_distribution_domain_name" {
  description = "CloudFront domain name for global video delivery."
  value       = aws_cloudfront_distribution.video_distribution.domain_name
}

output "cloudfront_url" {
  description = "HTTPS URL of the CloudFront distribution."
  value       = "https://${aws_cloudfront_distribution.video_distribution.domain_name}"
}