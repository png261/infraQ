terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
  description = "The DNS record name to map to the IPv4 address."
  type        = string
  default     = "www.example.com"
}

variable "ipv4_address" {
  description = "The IPv4 address that the DNS A record should point to."
  type        = string
  default     = "203.0.113.10"
}

variable "record_ttl" {
  description = "TTL in seconds for the DNS record."
  type        = number
  default     = 300
}

resource "aws_route53_zone" "main" {
  name = var.domain_name
}

resource "aws_route53_record" "ipv4_a_record" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.record_name
  type    = "A"
  ttl     = var.record_ttl
  records = [var.ipv4_address]
}

output "hosted_zone_id" {
  description = "The ID of the Route 53 hosted zone."
  value       = aws_route53_zone.main.zone_id
}

output "name_servers" {
  description = "The authoritative name servers for the hosted zone. Configure these at your domain registrar."
  value       = aws_route53_zone.main.name_servers
}

output "dns_record_fqdn" {
  description = "The fully qualified domain name of the created A record."
  value       = aws_route53_record.ipv4_a_record.fqdn
}

output "mapped_ipv4_address" {
  description = "The IPv4 address mapped to the DNS record."
  value       = var.ipv4_address
}