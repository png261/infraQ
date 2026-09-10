resource "aws_lightsail_bucket" "origin" {
  name      = "iac-eval-origin-bucket"
  bundle_id = "small_1_0"
}

resource "aws_lightsail_distribution" "cdn" {
  name      = "iac-eval-distribution"
  bundle_id = "small_1_0"

  default_cache_behavior {
    behavior = "cache"
  }

  origin {
    name        = aws_lightsail_bucket.origin.name
    region_name = "us-east-1"
  }

  cache_behavior_settings {
    forwarded_cookies {
      cookies_allow_list = ["session_id"]
    }

    forwarded_headers {
      headers_allow_list = ["Accept-Language"]
    }

    forwarded_query_strings {
      query_strings_allowed_list = ["version"]
    }
  }
}
