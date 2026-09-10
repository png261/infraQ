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

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr_block" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "route_destination_cidr_block" {
  description = "Specific CIDR block whose traffic should be routed through the Internet Gateway."
  type        = string
  default     = "0.0.0.0/0"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "custom-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "custom-vpc-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_block
  map_public_ip_on_launch = true

  tags = {
    Name = "custom-public-subnet"
  }
}

resource "aws_route_table" "custom" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "custom-route-table"
  }
}

resource "aws_route" "internet_gateway_route" {
  route_table_id         = aws_route_table.custom.id
  destination_cidr_block = var.route_destination_cidr_block
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.custom.id
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "internet_gateway_id" {
  description = "ID of the attached Internet Gateway."
  value       = aws_internet_gateway.main.id
}

output "custom_route_table_id" {
  description = "ID of the custom route table."
  value       = aws_route_table.custom.id
}

output "route_destination_cidr_block" {
  description = "CIDR block routed through the Internet Gateway."
  value       = var.route_destination_cidr_block
}