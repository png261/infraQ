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

variable "zone_name" {
  description = "The DNS name for the Route 53 hosted zone."
  type        = string
  default     = "primary.example.com"
}

variable "record_name" {
  description = "The DNS record name to route users through."
  type        = string
  default     = "app.primary.example.com"
}

variable "us_east_1_endpoint_ip" {
  description = "IPv4 address of the endpoint in us-east-1."
  type        = string
  default     = "203.0.113.10"
}

variable "eu_central_1_endpoint_ip" {
  description = "IPv4 address of the endpoint in eu-central-1."
  type        = string
  default     = "203.0.113.20"
}

resource "aws_route53_zone" "primary" {
  name = var.zone_name

  comment = "Primary hosted zone for latency-based routing"
}

resource "aws_route53_health_check" "us_east_1" {
  ip_address        = var.us_east_1_endpoint_ip
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name   = "us-east-1-endpoint-health-check"
    Region = "us-east-1"
  }
}

resource "aws_route53_health_check" "eu_central_1" {
  ip_address        = var.eu_central_1_endpoint_ip
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name   = "eu-central-1-endpoint-health-check"
    Region = "eu-central-1"
  }
}

resource "aws_route53_record" "us_east_1_latency" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = var.record_name
  type    = "A"
  ttl     = 60

  set_identifier = "us-east-1-latency-endpoint"

  latency_routing_policy {
    region = "us-east-1"
  }

  health_check_id = aws_route53_health_check.us_east_1.id

  records = [
    var.us_east_1_endpoint_ip
  ]
}

resource "aws_route53_record" "eu_central_1_latency" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = var.record_name
  type    = "A"
  ttl     = 60

  set_identifier = "eu-central-1-latency-endpoint"

  latency_routing_policy {
    region = "eu-central-1"
  }

  health_check_id = aws_route53_health_check.eu_central_1.id

  records = [
    var.eu_central_1_endpoint_ip
  ]
}

output "hosted_zone_id" {
  description = "The Route 53 hosted zone ID."
  value       = aws_route53_zone.primary.zone_id
}

output "hosted_zone_name_servers" {
  description = "Name servers assigned to the Route 53 hosted zone."
  value       = aws_route53_zone.primary.name_servers
}

output "latency_routed_dns_name" {
  description = "DNS name using Route 53 latency-based routing."
  value       = var.record_name
}