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

resource "aws_vpc" "specified_vpc" {
  cidr_block                       = var.vpc_cidr_block
  assign_generated_ipv6_cidr_block = true
  enable_dns_support               = true
  enable_dns_hostnames             = true

  tags = {
    Name        = "specified-vpc"
    permissions = "true"
  }
}

resource "aws_subnet" "ipv6_enabled_subnet" {
  vpc_id                          = aws_vpc.specified_vpc.id
  cidr_block                      = var.subnet_cidr_block
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.specified_vpc.ipv6_cidr_block, 8, 1)
  assign_ipv6_address_on_creation = true
  availability_zone               = "us-east-1a"

  tags = {
    Name        = "ipv6-enabled-subnet"
    permissions = "true"
  }
}

resource "aws_egress_only_internet_gateway" "pike" {
  vpc_id = aws_vpc.specified_vpc.id

  tags = {
    Name        = "pike"
    permissions = "true"
  }
}

resource "aws_route_table" "ipv6_egress_route_table" {
  vpc_id = aws_vpc.specified_vpc.id

  route {
    ipv6_cidr_block                = "::/0"
    egress_only_gateway_id         = aws_egress_only_internet_gateway.pike.id
  }

  tags = {
    Name        = "ipv6-egress-route-table"
    permissions = "true"
  }
}

resource "aws_route_table_association" "ipv6_subnet_association" {
  subnet_id      = aws_subnet.ipv6_enabled_subnet.id
  route_table_id = aws_route_table.ipv6_egress_route_table.id
}

output "vpc_id" {
  description = "ID of the VPC associated with the egress-only internet gateway."
  value       = aws_vpc.specified_vpc.id
}

output "egress_only_internet_gateway_id" {
  description = "ID of the egress-only internet gateway named pike."
  value       = aws_egress_only_internet_gateway.pike.id
}

output "subnet_ipv6_cidr_block" {
  description = "IPv6 CIDR block assigned to the IPv6-enabled subnet."
  value       = aws_subnet.ipv6_enabled_subnet.ipv6_cidr_block
}