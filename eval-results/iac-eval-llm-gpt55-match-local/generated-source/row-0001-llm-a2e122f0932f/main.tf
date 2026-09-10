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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "private_zone_name" {
  description = "Name of the private Route 53 hosted zone."
  type        = string
  default     = "internal.example.com"
}

resource "aws_vpc" "primary" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "primary-vpc"
  }
}

resource "aws_vpc" "secondary" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "secondary-vpc"
  }
}

resource "aws_route53_zone" "private" {
  name = var.private_zone_name

  vpc {
    vpc_id     = aws_vpc.primary.id
    vpc_region = var.aws_region
  }

  comment = "Private hosted zone associated with multiple VPCs"

  tags = {
    Name = "private-route53-zone"
  }
}

resource "aws_route53_zone_association" "secondary_vpc_association" {
  zone_id    = aws_route53_zone.private.zone_id
  vpc_id     = aws_vpc.secondary.id
  vpc_region = var.aws_region
}

output "route53_zone_id" {
  description = "ID of the private Route 53 hosted zone."
  value       = aws_route53_zone.private.zone_id
}

output "primary_vpc_id" {
  description = "ID of the primary VPC initially associated with the hosted zone."
  value       = aws_vpc.primary.id
}

output "secondary_vpc_id" {
  description = "ID of the secondary VPC associated using aws_route53_zone_association."
  value       = aws_vpc.secondary.id
}