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
  description = "AWS region to use for the Lightsail certificate."
  type        = string
  default     = "us-east-1"
}

variable "certificate_name" {
  description = "Name of the Lightsail certificate."
  type        = string
  default     = "example-lightsail-certificate"
}

variable "domain_name" {
  description = "Primary domain name for the Lightsail certificate."
  type        = string
  default     = "example.com"
}

variable "subject_alternative_names" {
  description = "Additional domain names to include in the Lightsail certificate."
  type        = list(string)
  default     = ["www.example.com"]
}

resource "aws_lightsail_certificate" "this" {
  name                      = var.certificate_name
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
}

output "lightsail_certificate_name" {
  description = "The name of the Lightsail certificate."
  value       = aws_lightsail_certificate.this.name
}

output "lightsail_certificate_domain_name" {
  description = "The primary domain name of the Lightsail certificate."
  value       = aws_lightsail_certificate.this.domain_name
}

output "lightsail_certificate_arn" {
  description = "The ARN of the Lightsail certificate."
  value       = aws_lightsail_certificate.this.arn
}

output "lightsail_certificate_status" {
  description = "The current status of the Lightsail certificate."
  value       = aws_lightsail_certificate.this.status
}

output "lightsail_certificate_domain_validation_options" {
  description = "DNS validation records required to validate the Lightsail certificate."
  value       = aws_lightsail_certificate.this.domain_validation_options
}