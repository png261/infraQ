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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name tag applied to all resources."
  type        = string
  default     = "dedicated-tenancy-vpc"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the dedicated-tenancy VPC."
  type        = string
  default     = "10.0.0.0/16"
}

resource "aws_vpc" "dedicated" {
  cidr_block           = var.vpc_cidr_block
  instance_tenancy     = "dedicated"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.name
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.dedicated.id

  tags = {
    Name = var.name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.dedicated.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = var.name
  }
}

output "vpc_id" {
  description = "ID of the dedicated-tenancy VPC."
  value       = aws_vpc.dedicated.id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway."
  value       = aws_internet_gateway.main.id
}

output "route_table_id" {
  description = "ID of the route table for outbound internet access."
  value       = aws_route_table.public.id
}