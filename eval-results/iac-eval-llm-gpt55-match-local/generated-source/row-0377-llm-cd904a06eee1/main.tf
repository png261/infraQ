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

variable "aws_region" {
  description = "AWS region where the Lightsail bucket and distribution will be created."
  type        = string
  default     = "us-east-1"
}

variable "bucket_base_name" {
  description = "Base name for the Lightsail bucket. A random suffix will be added for global uniqueness."
  type        = string
  default     = "lightsail-origin-bucket"
}

variable "bucket_bundle_id" {
  description = "Lightsail bucket bundle ID."
  type        = string
  default     = "small_1_0"
}

variable "distribution_name" {
  description = "Name of the Lightsail distribution."
  type        = string
  default     = "lightsail-bucket-distribution"
}

variable "distribution_bundle_id" {
  description = "Lightsail distribution bundle ID."
  type        = string
  default     = "small_1_0"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_lightsail_bucket" "origin" {
  name      = "${var.bucket_base_name}-${random_id.bucket_suffix.hex}"
  bundle_id = var.bucket_bundle_id

  access_rules {
    get_object = "private"
  }
}

resource "aws_lightsail_distribution" "cdn" {
  name      = var.distribution_name
  bundle_id = var.distribution_bundle_id

  origin {
    name        = aws_lightsail_bucket.origin.name
    region_name = var.aws_region
  }

  default_cache_behavior {
    behavior = "cache"
  }

  cache_behavior_settings {
    default_ttl               = 86400
    minimum_ttl               = 0
    maximum_ttl               = 31536000
    allowed_http_methods      = "GET,HEAD"
    cached_http_methods       = "GET,HEAD"
    forwarded_cookies {
      option = "none"
    }
    forwarded_headers {
      option = "none"
    }
    forwarded_query_strings {
      option = false
    }
  }

  depends_on = [
    aws_lightsail_bucket.origin
  ]
}

resource "aws_lightsail_bucket_resource_access" "distribution_access" {
  bucket_name   = aws_lightsail_bucket.origin.name
  resource_name = aws_lightsail_distribution.cdn.name
}

output "lightsail_bucket_name" {
  description = "Name of the Lightsail bucket used as the distribution origin."
  value       = aws_lightsail_bucket.origin.name
}

output "lightsail_distribution_name" {
  description = "Name of the Lightsail distribution."
  value       = aws_lightsail_distribution.cdn.name
}

output "lightsail_distribution_domain_name" {
  description = "Domain name of the Lightsail distribution."
  value       = aws_lightsail_distribution.cdn.domain_name
}