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
  description = "AWS region used for the provider configuration. Route 53 is global, but the AWS provider still requires a region."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "The root domain name for the Route 53 hosted zone."
  type        = string
  default     = "example.com"
}

variable "record_name" {
  description = "The DNS record name to create inside the hosted zone."
  type        = string
  default     = "www"
}

variable "ipv4_address" {
  description = "The IPv4 address that the DNS A record should point to."
  type        = string
  default     = "203.0.113.10"
}

variable "record_ttl" {
  description = "The TTL, in seconds, for the DNS record."
  type        = number
  default     = 300
}

resource "aws_route53_zone" "primary" {
  name = var.domain_name
}

resource "aws_route53_record" "a_record" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "${var.record_name}.${var.domain_name}"
  type    = "A"
  ttl     = var.record_ttl
  records = [var.ipv4_address]
}

output "hosted_zone_id" {
  description = "The ID of the Route 53 hosted zone."
  value       = aws_route53_zone.primary.zone_id
}

output "name_servers" {
  description = "The name servers assigned to the Route 53 hosted zone. Configure these at your domain registrar."
  value       = aws_route53_zone.primary.name_servers
}

output "dns_record_fqdn" {
  description = "The fully qualified domain name of the created A record."
  value       = aws_route53_record.a_record.fqdn
}

output "dns_record_ipv4_address" {
  description = "The IPv4 address mapped to the DNS A record."
  value       = var.ipv4_address
}