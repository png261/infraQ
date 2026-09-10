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

variable "root_domain_name" {
  description = "The root domain name for the Route53 hosted zone."
  type        = string
  default     = "example.com"
}

variable "video_domain_name" {
  description = "The DNS name used for the video streaming CloudFront distribution."
  type        = string
  default     = "video.example.com"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name for storing video content."
  type        = string
  default     = "global-video-streaming-content-example-123456"
}

resource "aws_route53_zone" "video_zone" {
  name = var.root_domain_name
}

resource "aws_s3_bucket" "video_content" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_ownership_controls" "video_content" {
  bucket = aws_s3_bucket.video_content.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "video_content" {
  bucket = aws_s3_bucket.video_content.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "video_content" {
  bucket = aws_s3_bucket.video_content.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "sample_video" {
  bucket       = aws_s3_bucket.video_content.id
  key          = "videos/sample-video.txt"
  content      = "This is a placeholder object representing video content."
  content_type = "text/plain"

  depends_on = [
    aws_s3_bucket_ownership_controls.video_content,
    aws_s3_bucket_public_access_block.video_content
  ]
}

resource "aws_acm_certificate" "video_cert" {
  domain_name       = var.video_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "video_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.video_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.video_zone.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "video_cert" {
  certificate_arn         = aws_acm_certificate.video_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.video_cert_validation : record.fqdn]
}

resource "aws_cloudfront_origin_access_control" "video_oac" {
  name                              = "video-streaming-s3-oac"
  description                       = "Origin Access Control for private S3 video content"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "video_distribution" {
  enabled             = true
  comment             = "Global CloudFront distribution for video streaming content"
  default_root_object = ""

  aliases = [
    var.video_domain_name
  ]

  origin {
    domain_name              = aws_s3_bucket.video_content.bucket_regional_domain_name
    origin_id                = "s3-video-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.video_oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-video-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = [
      "GET",
      "HEAD",
      "OPTIONS"
    ]

    cached_methods = [
      "GET",
      "HEAD",
      "OPTIONS"
    ]

    compress = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  ordered_cache_behavior {
    path_pattern           = "videos/*"
    target_origin_id       = "s3-video-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = [
      "GET",
      "HEAD",
      "OPTIONS"
    ]

    cached_methods = [
      "GET",
      "HEAD",
      "OPTIONS"
    ]

    compress = false

    forwarded_values {
      query_string = true

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.video_cert.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [
    aws_acm_certificate_validation.video_cert
  ]
}

resource "aws_s3_bucket_policy" "allow_cloudfront_read" {
  bucket = aws_s3_bucket.video_content.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipalReadOnly"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.video_content.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.video_distribution.arn
          }
        }
      }
    ]
  })
}

resource "aws_route53_record" "video_cloudfront_alias" {
  zone_id = aws_route53_zone.video_zone.zone_id
  name    = var.video_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.video_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.video_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "video_cloudfront_ipv6_alias" {
  zone_id = aws_route53_zone.video_zone.zone_id
  name    = var.video_domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.video_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.video_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

output "s3_bucket_name" {
  description = "Name of the private S3 bucket storing video content."
  value       = aws_s3_bucket.video_content.bucket
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  value       = aws_cloudfront_distribution.video_distribution.id
}

output "cloudfront_distribution_domain_name" {
  description = "CloudFront distribution domain name."
  value       = aws_cloudfront_distribution.video_distribution.domain_name
}

output "video_site_url" {
  description = "HTTPS URL for the video streaming domain."
  value       = "https://${var.video_domain_name}/videos/sample-video.txt"
}

output "route53_name_servers" {
  description = "Name servers for the Route53 hosted zone. Configure these at your domain registrar."
  value       = aws_route53_zone.video_zone.name_servers
}