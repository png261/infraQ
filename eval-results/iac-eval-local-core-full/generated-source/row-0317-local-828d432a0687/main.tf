locals {
  domain_name = "example.com"
  origin_id   = "s3-video-content-origin"
}

resource "aws_s3_bucket" "video_content" {
  bucket = "video-content-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_cloudfront_origin_access_control" "video_content" {
  name                              = "video-content-oac"
  description                       = "Origin access control for video content bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "video_content" {
  enabled             = true
  comment             = "Video streaming content distribution"
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

resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.video_content.id
  policy = data.aws_iam_policy_document.allow_cloudfront.json
}

data "aws_iam_policy_document" "allow_cloudfront" {
  statement {
    sid = "AllowCloudFrontServicePrincipalReadOnly"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.video_content.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.video_content.arn]
    }
  }
}

resource "aws_route53_zone" "video" {
  name = local.domain_name
}

resource "aws_route53_record" "video" {
  zone_id = aws_route53_zone.video.zone_id
  name    = "video.${aws_route53_zone.video.name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.video_content.domain_name
    zone_id                = aws_cloudfront_distribution.video_content.hosted_zone_id
    evaluate_target_health = false
  }
}
