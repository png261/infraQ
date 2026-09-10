data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "iac-eval-lightsail-origin"
}

resource "aws_lightsail_instance" "origin" {
  name              = "${local.name_prefix}-instance"
  availability_zone = data.aws_availability_zones.available.names[0]
  blueprint_id      = "amazon_linux_2"
  bundle_id         = "nano_3_0"
}

resource "aws_lightsail_static_ip" "origin" {
  name = "${local.name_prefix}-static-ip"
}

resource "aws_lightsail_static_ip_attachment" "origin" {
  static_ip_name = aws_lightsail_static_ip.origin.name
  instance_name  = aws_lightsail_instance.origin.name
}

resource "aws_lightsail_distribution" "origin" {
  name      = "${local.name_prefix}-distribution"
  bundle_id = "small_1_0"

  origin {
    name            = aws_lightsail_static_ip.origin.name
    region_name     = "us-east-1"
    protocol_policy = "http-only"
  }

  default_cache_behavior {
    behavior = "cache"
  }

  cache_behavior_settings {
    allowed_http_methods = "GET,HEAD,OPTIONS,PUT,PATCH,POST,DELETE"
    cached_http_methods  = "GET,HEAD"
    default_ttl          = 86400
    maximum_ttl          = 31536000
    minimum_ttl          = 0

    forwarded_cookies {
      option             = "allow-list"
      cookies_allow_list = ["session_id"]
    }

    forwarded_headers {
      option             = "allow-list"
      headers_allow_list = ["Host"]
    }

    forwarded_query_strings {
      option                     = true
      query_strings_allowed_list = ["version"]
    }
  }

  depends_on = [aws_lightsail_static_ip_attachment.origin]
}
