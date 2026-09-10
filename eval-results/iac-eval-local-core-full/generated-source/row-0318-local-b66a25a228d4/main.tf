data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "cloudfront_oac_access" {
  statement {
    sid     = "AllowCloudFrontServicePrincipalReadOnly"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.video_content.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.video_distribution.arn]
    }
  }
}

resource "aws_s3_bucket" "video_content" {
  bucket = "video-streaming-content-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "video_content" {
  bucket = aws_s3_bucket.video_content.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "video_content" {
  bucket = aws_s3_bucket.video_content.id
  policy = data.aws_iam_policy_document.cloudfront_oac_access.json
}

resource "aws_cloudfront_origin_access_control" "video_oac" {
  name                              = "video-streaming-s3-oac"
  description                       = "Origin access control for video content S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "video_distribution" {
  enabled             = true
  comment             = "Global distribution for video streaming content"
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.video_content.bucket_regional_domain_name
    origin_id                = "s3-video-content-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.video_oac.id

    s3_origin_config {
      origin_access_identity = ""
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-video-content-origin"
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

resource "aws_route53_zone" "video_site" {
  name = "example-video-streaming.com"
}

resource "aws_route53_record" "video_site" {
  zone_id = aws_route53_zone.video_site.zone_id
  name    = "www.${aws_route53_zone.video_site.name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.video_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.video_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}
