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
  description = "AWS region where the Lightsail resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability zone for the Lightsail instance."
  type        = string
  default     = "us-east-1a"
}

variable "lightsail_instance_name" {
  description = "Name of the Lightsail instance."
  type        = string
  default     = "lightsail-origin-instance"
}

variable "lightsail_distribution_name" {
  description = "Name of the Lightsail distribution."
  type        = string
  default     = "lightsail-cdn-distribution"
}

variable "instance_blueprint_id" {
  description = "Lightsail blueprint ID for the instance operating system."
  type        = string
  default     = "amazon_linux_2"
}

variable "instance_bundle_id" {
  description = "Lightsail bundle ID for the instance size."
  type        = string
  default     = "nano_3_0"
}

variable "distribution_bundle_id" {
  description = "Lightsail distribution bundle ID."
  type        = string
  default     = "small_1_0"
}

resource "aws_lightsail_instance" "origin" {
  name              = var.lightsail_instance_name
  availability_zone = var.availability_zone
  blueprint_id      = var.instance_blueprint_id
  bundle_id         = var.instance_bundle_id

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install nginx1 -y
    systemctl enable nginx
    systemctl start nginx

    cat > /usr/share/nginx/html/index.html <<HTML
    <!DOCTYPE html>
    <html>
      <head>
        <title>Lightsail Origin</title>
      </head>
      <body>
        <h1>Hello from AWS Lightsail</h1>
        <p>This content is served from a Lightsail instance behind a Lightsail Distribution.</p>
      </body>
    </html>
    HTML
  EOF

  tags = {
    Name        = var.lightsail_instance_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

resource "aws_lightsail_instance_public_ports" "origin_http" {
  instance_name = aws_lightsail_instance.origin.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
  }

  port_info {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
  }
}

resource "aws_lightsail_distribution" "cdn" {
  name      = var.lightsail_distribution_name
  bundle_id = var.distribution_bundle_id
  is_enabled = true

  origin {
    name            = aws_lightsail_instance.origin.name
    region_name     = var.aws_region
    protocol_policy = "http-only"
  }

  default_cache_behavior {
    behavior = "cache"
  }

  cache_behavior_settings {
    allowed_http_methods = "GET,HEAD,OPTIONS,PUT,PATCH,POST,DELETE"
    cached_http_methods  = "GET,HEAD"

    default_ttl = 86400
    minimum_ttl = 0
    maximum_ttl = 31536000

    forwarded_cookies {
      option = "none"
    }

    forwarded_headers {
      option = "default"
    }

    forwarded_query_strings {
      option = false
    }
  }

  depends_on = [
    aws_lightsail_instance_public_ports.origin_http
  ]

  tags = {
    Name        = var.lightsail_distribution_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

output "lightsail_instance_name" {
  description = "Name of the Lightsail origin instance."
  value       = aws_lightsail_instance.origin.name
}

output "lightsail_instance_public_ip" {
  description = "Public IP address of the Lightsail origin instance."
  value       = aws_lightsail_instance.origin.public_ip_address
}

output "lightsail_distribution_name" {
  description = "Name of the Lightsail distribution."
  value       = aws_lightsail_distribution.cdn.name
}

output "lightsail_distribution_domain_name" {
  description = "Domain name of the Lightsail distribution."
  value       = aws_lightsail_distribution.cdn.domain_name
}