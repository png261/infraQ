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
  region = "us-east-1"
}

variable "reverse_zone_domain" {
  description = "Reverse DNS hosted zone domain."
  type        = string
  default     = "2.0.192.in-addr.arpa"
}

variable "ptr_record_name" {
  description = "PTR record name for the reverse DNS entry."
  type        = string
  default     = "44.2.0.192.in-addr.arpa"
}

variable "forward_domain_name" {
  description = "Forward hostname that the PTR record resolves to."
  type        = string
  default     = "host.example53.com"
}

resource "aws_route53_zone" "reverse_zone" {
  name = var.reverse_zone_domain

  comment = "Reverse DNS hosted zone for PTR records"
}

resource "aws_route53_record" "ptr_record" {
  zone_id = aws_route53_zone.reverse_zone.zone_id
  name    = var.ptr_record_name
  type    = "PTR"
  ttl     = 300

  records = [
    "${var.forward_domain_name}."
  ]
}

output "reverse_zone_id" {
  description = "The Route 53 hosted zone ID for the reverse DNS zone."
  value       = aws_route53_zone.reverse_zone.zone_id
}

output "reverse_zone_name_servers" {
  description = "Name servers assigned to the reverse DNS hosted zone."
  value       = aws_route53_zone.reverse_zone.name_servers
}

output "ptr_record_fqdn" {
  description = "The fully qualified PTR record name."
  value       = aws_route53_record.ptr_record.fqdn
}