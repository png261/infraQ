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
  description = "AWS region used for Route 53 API operations."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "The root domain name for the Route 53 hosted zone."
  type        = string
  default     = "example.com"
}

variable "record_name" {
  description = "The DNS record name to map to the IPv6 address."
  type        = string
  default     = "www.example.com"
}

variable "ipv6_address" {
  description = "The IPv6 address that the DNS record should resolve to."
  type        = string
  default     = "2001:db8::1"
}

variable "record_ttl" {
  description = "The TTL for the DNS record in seconds."
  type        = number
  default     = 300
}

resource "aws_route53_zone" "main" {
  name = var.domain_name
}

resource "aws_route53_record" "ipv6_record" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.record_name
  type    = "AAAA"
  ttl     = var.record_ttl
  records = [var.ipv6_address]
}

output "hosted_zone_id" {
  description = "The ID of the Route 53 hosted zone."
  value       = aws_route53_zone.main.zone_id
}

output "hosted_zone_name_servers" {
  description = "The authoritative name servers for the hosted zone."
  value       = aws_route53_zone.main.name_servers
}

output "aaaa_record_fqdn" {
  description = "The fully qualified domain name of the AAAA record."
  value       = aws_route53_record.ipv6_record.fqdn
}

output "aaaa_record_ipv6_address" {
  description = "The IPv6 address configured for the AAAA record."
  value       = var.ipv6_address
}