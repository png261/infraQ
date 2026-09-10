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
  description = "AWS region used for provider operations. Route 53 is global, but the provider still requires a region."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Domain name for the Route 53 hosted zone."
  type        = string
  default     = "example.com"
}

variable "service_record_name" {
  description = "DNS record name used for the active-active service endpoint."
  type        = string
  default     = "app"
}

variable "primary_endpoint_ip" {
  description = "IPv4 address for the primary endpoint."
  type        = string
  default     = "203.0.113.10"
}

variable "secondary_endpoint_ip" {
  description = "IPv4 address for the secondary endpoint."
  type        = string
  default     = "203.0.113.20"
}

variable "health_check_path" {
  description = "HTTP path used by Route 53 health checks."
  type        = string
  default     = "/"
}

resource "aws_route53_zone" "main" {
  name = var.domain_name
}

resource "aws_route53_record" "primary_endpoint" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "primary.${var.domain_name}"
  type    = "A"
  ttl     = 60

  records = [
    var.primary_endpoint_ip
  ]
}

resource "aws_route53_record" "secondary_endpoint" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "secondary.${var.domain_name}"
  type    = "A"
  ttl     = 60

  records = [
    var.secondary_endpoint_ip
  ]
}

resource "aws_route53_health_check" "primary_health_check" {
  fqdn              = aws_route53_record.primary_endpoint.fqdn
  port              = 80
  type              = "HTTP"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name = "primary_health_check"
  }
}

resource "aws_route53_health_check" "secondary_health_check" {
  fqdn              = aws_route53_record.secondary_endpoint.fqdn
  port              = 80
  type              = "HTTP"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name = "secondary_health_check"
  }
}

resource "aws_route53_record" "active_active_primary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.service_record_name}.${var.domain_name}"
  type    = "A"
  ttl     = 60

  set_identifier = "primary-active-active"

  weighted_routing_policy {
    weight = 100
  }

  health_check_id = aws_route53_health_check.primary_health_check.id

  records = [
    var.primary_endpoint_ip
  ]
}

resource "aws_route53_record" "active_active_secondary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.service_record_name}.${var.domain_name}"
  type    = "A"
  ttl     = 60

  set_identifier = "secondary-active-active"

  weighted_routing_policy {
    weight = 100
  }

  health_check_id = aws_route53_health_check.secondary_health_check.id

  records = [
    var.secondary_endpoint_ip
  ]
}

output "hosted_zone_id" {
  description = "ID of the Route 53 hosted zone named main."
  value       = aws_route53_zone.main.zone_id
}

output "service_fqdn" {
  description = "Active-active service FQDN."
  value       = aws_route53_record.active_active_primary.fqdn
}

output "primary_health_check_id" {
  description = "Route 53 health check ID for the primary endpoint."
  value       = aws_route53_health_check.primary_health_check.id
}

output "secondary_health_check_id" {
  description = "Route 53 health check ID for the secondary endpoint."
  value       = aws_route53_health_check.secondary_health_check.id
}