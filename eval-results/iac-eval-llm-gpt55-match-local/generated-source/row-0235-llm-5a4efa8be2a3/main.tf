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
  description = "AWS region where the VPC will be created."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr_block" {
  description = "IPv4 CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr_block" {
  description = "IPv4 CIDR block for the subnet."
  type        = string
  default     = "10.0.1.0/24"
}

resource "aws_vpc" "main" {
  cidr_block                       = var.vpc_cidr_block
  assign_generated_ipv6_cidr_block = true
  enable_dns_support               = true
  enable_dns_hostnames             = true

  tags = {
    Name = "egress-only-igw-vpc"
  }
}

resource "aws_egress_only_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "egress-only-internet-gateway"
  }
}

resource "aws_subnet" "main" {
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = var.subnet_cidr_block
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 1)
  assign_ipv6_address_on_creation = true
  availability_zone               = "${var.aws_region}a"

  tags = {
    Name = "ipv6-egress-subnet"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.main.id
  }

  tags = {
    Name = "ipv6-egress-route-table"
  }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "vpc_ipv4_cidr_block" {
  description = "IPv4 CIDR block of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "vpc_ipv6_cidr_block" {
  description = "IPv6 CIDR block assigned to the VPC."
  value       = aws_vpc.main.ipv6_cidr_block
}

output "egress_only_internet_gateway_id" {
  description = "ID of the Egress-Only Internet Gateway."
  value       = aws_egress_only_internet_gateway.main.id
}

output "subnet_id" {
  description = "ID of the IPv6-enabled subnet."
  value       = aws_subnet.main.id
}