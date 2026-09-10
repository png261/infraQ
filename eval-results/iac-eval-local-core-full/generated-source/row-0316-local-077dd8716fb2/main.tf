locals {
  origin_id = "video-content-s3-origin"
}

resource "aws_s3_bucket" "video_content" {
  bucket_prefix = "video-streaming-content-"
}

resource "aws_cloudfront_origin_access_control" "video_content" {
  name                              = "video-content-s3-oac"
  description                       = "Origin access control for the video content S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "video_cdn" {
  enabled             = true
  comment             = "Global CDN for video streaming content"
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.video_content.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.video_content.id
    origin_id                = local.origin_id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "allow-all"
    compress               = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_route53_zone" "video_site" {
  name = var.domain_name
}

resource "aws_route53_record" "video" {
  zone_id = aws_route53_zone.video_site.zone_id
  name    = "${var.record_name}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.video_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.video_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}
