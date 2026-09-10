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
  description = "AWS region used for provider configuration."
  type        = string
  default     = "us-east-1"
}

variable "zone_name" {
  description = "The DNS name for the Route 53 hosted zone."
  type        = string
  default     = "example.com"
}

variable "application_record_name" {
  description = "The DNS record name used for active-passive failover."
  type        = string
  default     = "app.example.com"
}

variable "primary_endpoint_fqdn" {
  description = "The fully qualified domain name of the primary endpoint."
  type        = string
  default     = "primary-origin.example.com"
}

variable "secondary_endpoint_fqdn" {
  description = "The fully qualified domain name of the secondary endpoint."
  type        = string
  default     = "secondary-origin.example.com"
}

resource "aws_route53_zone" "primary" {
  name = var.zone_name

  comment = "Primary hosted zone for active-passive Route 53 failover."
}

resource "aws_route53_health_check" "primary_health_check" {
  fqdn              = var.primary_endpoint_fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name = "primary_health_check"
  }
}

resource "aws_route53_record" "primary_failover" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = var.application_record_name
  type    = "CNAME"
  ttl     = 60

  records = [
    var.primary_endpoint_fqdn
  ]

  set_identifier = "primary-active-record"

  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.primary_health_check.id
}

resource "aws_route53_record" "secondary_failover" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = var.application_record_name
  type    = "CNAME"
  ttl     = 60

  records = [
    var.secondary_endpoint_fqdn
  ]

  set_identifier = "secondary-passive-record"

  failover_routing_policy {
    type = "SECONDARY"
  }
}

output "hosted_zone_id" {
  description = "The ID of the Route 53 hosted zone."
  value       = aws_route53_zone.primary.zone_id
}

output "hosted_zone_name_servers" {
  description = "Name servers assigned to the Route 53 hosted zone."
  value       = aws_route53_zone.primary.name_servers
}

output "primary_health_check_id" {
  description = "The ID of the primary Route 53 health check."
  value       = aws_route53_health_check.primary_health_check.id
}

output "failover_dns_name" {
  description = "The DNS name configured for active-passive failover."
  value       = var.application_record_name
}