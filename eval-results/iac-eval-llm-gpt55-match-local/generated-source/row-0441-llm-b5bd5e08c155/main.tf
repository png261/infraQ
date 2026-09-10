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

variable "vpc_id" {
  description = "Optional existing VPC ID to attach the egress-only internet gateway to. If empty, a new IPv6-enabled VPC is created."
  type        = string
  default     = ""
}

variable "existing_route_table_id" {
  description = "Optional existing route table ID to add the IPv6 default route to when using an existing VPC. If empty, no existing route table is modified."
  type        = string
  default     = ""
}

variable "vpc_cidr_block" {
  description = "IPv4 CIDR block for the new VPC when vpc_id is not supplied."
  type        = string
  default     = "10.50.0.0/16"
}

locals {
  create_vpc   = var.vpc_id == ""
  selected_vpc = local.create_vpc ? aws_vpc.ipv6_vpc[0].id : var.vpc_id
}

resource "aws_vpc" "ipv6_vpc" {
  count = local.create_vpc ? 1 : 0

  cidr_block                       = var.vpc_cidr_block
  assign_generated_ipv6_cidr_block = true
  enable_dns_support               = true
  enable_dns_hostnames             = true

  tags = {
    Name = "ipv6-egress-only-vpc"
  }
}

resource "aws_egress_only_internet_gateway" "ipv6_egress" {
  vpc_id = local.selected_vpc

  tags = {
    Name = "ipv6-egress-only-internet-gateway"
  }
}

resource "aws_route_table" "ipv6_egress_route_table" {
  count = local.create_vpc ? 1 : 0

  vpc_id = aws_vpc.ipv6_vpc[0].id

  tags = {
    Name = "ipv6-egress-only-route-table"
  }
}

resource "aws_route" "managed_vpc_ipv6_default_route" {
  count = local.create_vpc ? 1 : 0

  route_table_id              = aws_route_table.ipv6_egress_route_table[0].id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.ipv6_egress.id
}

resource "aws_route" "existing_vpc_ipv6_default_route" {
  count = local.create_vpc == false && var.existing_route_table_id != "" ? 1 : 0

  route_table_id              = var.existing_route_table_id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.ipv6_egress.id
}

output "vpc_id" {
  description = "The VPC ID associated with the egress-only internet gateway."
  value       = local.selected_vpc
}

output "egress_only_internet_gateway_id" {
  description = "The ID of the egress-only internet gateway."
  value       = aws_egress_only_internet_gateway.ipv6_egress.id
}

output "managed_route_table_id" {
  description = "The route table ID created for the managed VPC. Null when using an existing VPC."
  value       = local.create_vpc ? aws_route_table.ipv6_egress_route_table[0].id : null
}