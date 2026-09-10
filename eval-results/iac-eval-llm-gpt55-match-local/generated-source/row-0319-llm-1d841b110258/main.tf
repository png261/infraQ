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
  description = "AWS region used for regional resources such as S3."
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_name" {
  description = "Globally unique name for the S3 bucket used as the CloudFront origin."
  type        = string
  default     = "netflix-video-content-origin-example-123456789"
}

resource "aws_s3_bucket" "video_content" {
  bucket = var.s3_bucket_name
}

resource "aws_s3_bucket_public_access_block" "video_content" {
  bucket = aws_s3_bucket.video_content.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "s3_video_content_oac" {
  name                              = "s3-video-content-origin-access-control"
  description                       = "Origin access control for private S3 video content bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "video_content_distribution" {
  enabled         = true
  is_ipv6_enabled = true
  price_class     = "PriceClass_200"

  origin {
    domain_name              = aws_s3_bucket.video_content.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_video_content_oac.id
    origin_id                = "s3_video_content_origin"
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3_video_content_origin"
    viewer_protocol_policy = "allow-all"
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "allow_cloudfront_read_s3" {
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
      "${aws_s3_bucket.video_content.arn}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.video_content_distribution.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "video_content" {
  bucket = aws_s3_bucket.video_content.id
  policy = data.aws_iam_policy_document.allow_cloudfront_read_s3.json

  depends_on = [
    aws_s3_bucket_public_access_block.video_content
  ]
}

resource "aws_route53_zone" "netflix" {
  name = "netflix.com"
}

resource "aws_route53_record" "netflix_apex_a" {
  zone_id = aws_route53_zone.netflix.zone_id
  name    = aws_route53_zone.netflix.name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.video_content_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.video_content_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "netflix_apex_aaaa" {
  zone_id = aws_route53_zone.netflix.zone_id
  name    = aws_route53_zone.netflix.name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.video_content_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.video_content_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket used as the CloudFront origin."
  value       = aws_s3_bucket.video_content.bucket
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution."
  value       = aws_cloudfront_distribution.video_content_distribution.id
}

output "cloudfront_distribution_domain_name" {
  description = "Domain name of the CloudFront distribution."
  value       = aws_cloudfront_distribution.video_content_distribution.domain_name
}

output "route53_zone_id" {
  description = "ID of the Route53 hosted zone."
  value       = aws_route53_zone.netflix.zone_id
}

output "route53_name_servers" {
  description = "Name servers assigned to the Route53 hosted zone."
  value       = aws_route53_zone.netflix.name_servers
}