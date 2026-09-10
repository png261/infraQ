resource "aws_s3_bucket" "video_content" {
  bucket_prefix = "video-content-"
}

resource "aws_cloudfront_origin_access_control" "s3_video_content" {
  name                              = "s3-video-content-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "video_content" {
  enabled     = true
  price_class = "PriceClass_200"

  origin {
    domain_name              = aws_s3_bucket.video_content.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_video_content.id
    origin_id                = "s3_video_content_origin"
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3_video_content_origin"
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
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_route53_zone" "netflix" {
  name = "netflix.com"
}

resource "aws_route53_record" "cdn_a" {
  zone_id = aws_route53_zone.netflix.zone_id
  name    = "cdn"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.video_content.domain_name
    zone_id                = aws_cloudfront_distribution.video_content.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cdn_aaaa" {
  zone_id = aws_route53_zone.netflix.zone_id
  name    = "cdn"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.video_content.domain_name
    zone_id                = aws_cloudfront_distribution.video_content.hosted_zone_id
    evaluate_target_health = true
  }
}
