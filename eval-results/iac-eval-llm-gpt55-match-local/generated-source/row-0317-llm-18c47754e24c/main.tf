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

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

variable "aws_region" {
  description = "Primary AWS region for S3 and Route53 resources."
  type        = string
  default     = "us-west-2"
}

variable "domain_name" {
  description = "Root domain name for the video streaming site."
  type        = string
  default     = "video-streaming-example.com"
}

variable "cloudfront_price_class" {
  description = "CloudFront price class. PriceClass_All provides maximum global distribution."
  type        = string
  default     = "PriceClass_All"
}

variable "default_root_object" {
  description = "Default object served by CloudFront."
  type        = string
  default     = "index.html"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

locals {
  site_domain       = var.domain_name
  video_bucket_name = "video-origin-${replace(var.domain_name, ".", "-")}-${random_id.bucket_suffix.hex}"
}

resource "aws_route53_zone" "main" {
  name = var.domain_name

  comment = "Public hosted zone for ${var.domain_name}"
}

resource "aws_s3_bucket" "video_origin" {
  bucket = local.video_bucket_name

  tags = {
    Name        = "Video Streaming Origin Bucket"
    Environment = "production"
    Service     = "video-streaming"
  }
}

resource "aws_s3_bucket_versioning" "video_origin" {
  bucket = aws_s3_bucket.video_origin.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "video_origin" {
  bucket = aws_s3_bucket.video_origin.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "video_origin" {
  bucket = aws_s3_bucket.video_origin.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "video_origin" {
  bucket = aws_s3_bucket.video_origin.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.video_origin.id
  key          = "index.html"
  content_type = "text/html"

  content = <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>Global Video Streaming Site</title>
</head>
<body>
  <h1>Global Video Streaming Site</h1>
  <p>This site is served globally through Amazon CloudFront with private S3 origin storage.</p>
  <p>Upload your video files to the S3 bucket and distribute them using CloudFront URLs.</p>
</body>
</html>
EOF
}

resource "aws_acm_certificate" "cloudfront_cert" {
  provider = aws.us_east_1

  domain_name       = local.site_domain
  validation_method = "DNS"

  subject_alternative_names = [
    "www.${local.site_domain}"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "CloudFront Certificate for ${local.site_domain}"
    Environment = "production"
    Service     = "video-streaming"
  }
}

resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cloudfront_cert.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300

  records = [
    each.value.record
  ]
}

resource "aws_acm_certificate_validation" "cloudfront_cert" {
  provider = aws.us_east_1

  certificate_arn = aws_acm_certificate.cloudfront_cert.arn

  validation_record_fqdns = [
    for record in aws_route53_record.certificate_validation : record.fqdn
  ]
}

resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "video-streaming-s3-oac-${random_id.bucket_suffix.hex}"
  description                       = "Origin Access Control for private S3 video origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_cache_policy" "video_cache_policy" {
  name        = "video-streaming-cache-policy-${random_id.bucket_suffix.hex}"
  comment     = "Optimized cache policy for video streaming content"
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name    = "video-streaming-security-headers-${random_id.bucket_suffix.hex}"
  comment = "Security headers for video streaming distribution"

  security_headers_config {
    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    xss_protection {
      protection = true
      mode_block = true
      override   = true
    }
  }
}

resource "aws_cloudfront_distribution" "video_cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Global CloudFront CDN for ${local.site_domain}"
  default_root_object = var.default_root_object
  price_class         = var.cloudfront_price_class

  aliases = [
    local.site_domain,
    "www.${local.site_domain}"
  ]

  origin {
    domain_name              = aws_s3_bucket.video_origin.bucket_regional_domain_name
    origin_id                = "s3-video-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
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
      "HEAD"
    ]

    cache_policy_id            = aws_cloudfront_cache_policy.video_cache_policy.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id
    compress                   = true
  }

  ordered_cache_behavior {
    path_pattern           = "*.mp4"
    target_origin_id       = "s3-video-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = [
      "GET",
      "HEAD",
      "OPTIONS"
    ]

    cached_methods = [
      "GET",
      "HEAD"
    ]

    cache_policy_id            = aws_cloudfront_cache_policy.video_cache_policy.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id
    compress                   = false
  }

  ordered_cache_behavior {
    path_pattern           = "*.m3u8"
    target_origin_id       = "s3-video-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = [
      "GET",
      "HEAD",
      "OPTIONS"
    ]

    cached_methods = [
      "GET",
      "HEAD"
    ]

    cache_policy_id            = aws_cloudfront_cache_policy.video_cache_policy.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id
    compress                   = true
  }

  ordered_cache_behavior {
    path_pattern           = "*.ts"
    target_origin_id       = "s3-video-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = [
      "GET",
      "HEAD",
      "OPTIONS"
    ]

    cached_methods = [
      "GET",
      "HEAD"
    ]

    cache_policy_id            = aws_cloudfront_cache_policy.video_cache_policy.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id
    compress                   = false
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cloudfront_cert.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [
    aws_acm_certificate_validation.cloudfront_cert
  ]

  tags = {
    Name        = "Global Video Streaming CDN"
    Environment = "production"
    Service     = "video-streaming"
  }
}

resource "aws_s3_bucket_policy" "allow_cloudfront_access" {
  bucket = aws_s3_bucket.video_origin.id

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
        Resource = "${aws_s3_bucket.video_origin.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.video_cdn.arn
          }
        }
      }
    ]
  })
}

resource "aws_route53_record" "root_alias_ipv4" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.site_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.video_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.video_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "root_alias_ipv6" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.site_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.video_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.video_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www_alias_ipv4" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.${local.site_domain}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.video_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.video_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www_alias_ipv6" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.${local.site_domain}"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.video_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.video_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID."
  value       = aws_route53_zone.main.zone_id
}

output "route53_name_servers" {
  description = "Name servers for the Route53 hosted zone. Configure these at your domain registrar."
  value       = aws_route53_zone.main.name_servers
}

output "s3_video_origin_bucket" {
  description = "Private S3 bucket for video content uploads."
  value       = aws_s3_bucket.video_origin.bucket
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  value       = aws_cloudfront_distribution.video_cdn.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name."
  value       = aws_cloudfront_distribution.video_cdn.domain_name
}

output "site_url" {
  description = "Primary HTTPS URL for the video streaming site."
  value       = "https://${local.site_domain}"
}

output "www_site_url" {
  description = "WWW HTTPS URL for the video streaming site."
  value       = "https://www.${local.site_domain}"
}