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
  description = "AWS region used for provider operations. Route 53 is global, but the AWS provider still requires a region."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Domain name for the Route 53 hosted zone."
  type        = string
  default     = "example.com"
}

variable "record_name" {
  description = "DNS record name managed by the Route 53 traffic policy."
  type        = string
  default     = "app.example.com"
}

variable "endpoint_one_ip" {
  description = "First IPv4 endpoint for weighted routing."
  type        = string
  default     = "203.0.113.10"
}

variable "endpoint_two_ip" {
  description = "Second IPv4 endpoint for weighted routing."
  type        = string
  default     = "203.0.113.20"
}

resource "aws_route53_zone" "main" {
  name = var.domain_name

  comment = "Public hosted zone managed by Terraform for Route 53 traffic policy demo."
}

resource "aws_route53_traffic_policy" "weighted_policy" {
  name    = "weighted-a-record-policy"
  comment = "Weighted Route 53 traffic policy distributing traffic between two IPv4 endpoints."

  document = jsonencode({
    AWSPolicyFormatVersion = "2015-10-01"
    RecordType             = "A"

    Endpoints = {
      endpoint_one = {
        Type  = "value"
        Value = var.endpoint_one_ip
      }

      endpoint_two = {
        Type  = "value"
        Value = var.endpoint_two_ip
      }
    }

    Rules = {
      weighted_rule = {
        RuleType = "weighted"

        Items = [
          {
            EndpointReference = "endpoint_one"
            Weight            = 50
          },
          {
            EndpointReference = "endpoint_two"
            Weight            = 50
          }
        ]
      }
    }

    StartRule = "weighted_rule"
  })
}

resource "aws_route53_traffic_policy_instance" "app_record" {
  name                   = var.record_name
  hosted_zone_id         = aws_route53_zone.main.zone_id
  ttl                    = 60
  traffic_policy_id      = aws_route53_traffic_policy.weighted_policy.id
  traffic_policy_version = aws_route53_traffic_policy.weighted_policy.version
}

output "hosted_zone_id" {
  description = "The Route 53 hosted zone ID."
  value       = aws_route53_zone.main.zone_id
}

output "hosted_zone_name_servers" {
  description = "Name servers assigned to the Route 53 hosted zone."
  value       = aws_route53_zone.main.name_servers
}

output "traffic_policy_id" {
  description = "The Route 53 traffic policy ID."
  value       = aws_route53_traffic_policy.weighted_policy.id
}

output "traffic_policy_version" {
  description = "The Route 53 traffic policy version."
  value       = aws_route53_traffic_policy.weighted_policy.version
}

output "traffic_policy_record_fqdn" {
  description = "The DNS record created by the Route 53 traffic policy instance."
  value       = aws_route53_traffic_policy_instance.app_record.name
}