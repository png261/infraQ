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

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr_block" {
  description = "CIDR block for the public subnet where the NAT Gateway will be created."
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Availability Zone for the public subnet."
  type        = string
  default     = "us-east-1a"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "nat-gateway-vpc"
    pike = "permissions"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "nat-gateway-igw"
    pike = "permissions"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_block
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "nat-gateway-public-subnet"
    pike = "permissions"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "nat-gateway-public-route-table"
    pike = "permissions"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "nat-gateway-eip"
    pike = "permissions"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id     = aws_eip.nat.allocation_id
  subnet_id         = aws_subnet.public.id
  connectivity_type = "public"

  tags = {
    Name = "public-nat-gateway"
    pike = "permissions"
  }

  depends_on = [
    aws_internet_gateway.main,
    aws_route_table_association.public
  ]
}

output "nat_gateway_id" {
  description = "ID of the created NAT Gateway."
  value       = aws_nat_gateway.main.id
}

output "nat_gateway_public_ip" {
  description = "Public IP address associated with the NAT Gateway Elastic IP."
  value       = aws_eip.nat.public_ip
}

output "nat_gateway_allocation_id" {
  description = "Elastic IP allocation ID associated with the NAT Gateway."
  value       = aws_eip.nat.allocation_id
}

output "public_subnet_id" {
  description = "ID of the public subnet associated with the NAT Gateway."
  value       = aws_subnet.public.id
}