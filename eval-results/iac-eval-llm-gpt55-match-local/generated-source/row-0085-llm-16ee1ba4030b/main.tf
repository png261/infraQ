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
  description = "AWS region used by the provider. Route 53 is global, but AWS provider requires a region."
  type        = string
  default     = "us-east-1"
}

variable "zone_name" {
  description = "Name of the Route 53 hosted zone."
  type        = string
  default     = "primary"
}

variable "record_name" {
  description = "DNS record name used for geolocation routing."
  type        = string
  default     = "app"
}

variable "us_endpoint_ip" {
  description = "IPv4 address of the US endpoint."
  type        = string
  default     = "203.0.113.10"
}

variable "eu_endpoint_ip" {
  description = "IPv4 address of the EU endpoint."
  type        = string
  default     = "203.0.113.20"
}

variable "default_endpoint_ip" {
  description = "Fallback IPv4 address for users outside the configured geolocation routing areas."
  type        = string
  default     = "203.0.113.30"
}

resource "aws_route53_zone" "primary" {
  name = var.zone_name
}

resource "aws_route53_record" "us" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "${var.record_name}.${aws_route53_zone.primary.name}"
  type    = "A"
  ttl     = 60

  set_identifier = "US endpoint"

  geolocation_routing_policy {
    country = "US"
  }

  records = [
    var.us_endpoint_ip
  ]
}

resource "aws_route53_record" "eu" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "${var.record_name}.${aws_route53_zone.primary.name}"
  type    = "A"
  ttl     = 60

  set_identifier = "EU endpoint"

  geolocation_routing_policy {
    continent = "EU"
  }

  records = [
    var.eu_endpoint_ip
  ]
}

resource "aws_route53_record" "default" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "${var.record_name}.${aws_route53_zone.primary.name}"
  type    = "A"
  ttl     = 60

  set_identifier = "Default endpoint"

  geolocation_routing_policy {
    country = "*"
  }

  records = [
    var.default_endpoint_ip
  ]
}

output "hosted_zone_id" {
  description = "ID of the Route 53 hosted zone."
  value       = aws_route53_zone.primary.zone_id
}

output "hosted_zone_name_servers" {
  description = "Name servers assigned to the Route 53 hosted zone."
  value       = aws_route53_zone.primary.name_servers
}

output "geolocation_record_fqdn" {
  description = "Fully qualified domain name for the geolocation-routed record."
  value       = aws_route53_record.us.fqdn
}