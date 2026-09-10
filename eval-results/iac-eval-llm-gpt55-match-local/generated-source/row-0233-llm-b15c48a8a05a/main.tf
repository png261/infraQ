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
  region = "us-east-1"
}

resource "aws_vpc" "example" {
  cidr_block                       = "10.0.0.0/16"
  assign_generated_ipv6_cidr_block = true

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "example-ipv6-vpc"
    Environment = "example"
  }
}

output "vpc_id" {
  description = "The ID of the created VPC"
  value       = aws_vpc.example.id
}

output "ipv4_cidr_block" {
  description = "The IPv4 CIDR block assigned to the VPC"
  value       = aws_vpc.example.cidr_block
}

output "ipv6_cidr_block" {
  description = "The AWS-generated IPv6 CIDR block assigned to the VPC"
  value       = aws_vpc.example.ipv6_cidr_block
}