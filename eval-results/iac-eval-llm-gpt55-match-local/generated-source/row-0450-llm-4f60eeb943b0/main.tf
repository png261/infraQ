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

variable "existing_subnet_id" {
  description = "Optional existing subnet ID for the Private NAT Gateway. If empty, a new VPC and subnet are created."
  type        = string
  default     = ""
}

variable "elastic_ip_allocation_id" {
  description = "Optional Elastic IP allocation ID. Note: AWS Private NAT Gateways do not support Elastic IP allocation IDs, so this value is not attached."
  type        = string
  default     = ""
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC created when existing_subnet_id is not provided."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr_block" {
  description = "CIDR block for the subnet created when existing_subnet_id is not provided."
  type        = string
  default     = "10.0.1.0/24"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "nat_vpc" {
  count = var.existing_subnet_id == "" ? 1 : 0

  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "private-nat-vpc"
    pike = "permissions"
  }
}

resource "aws_subnet" "nat_subnet" {
  count = var.existing_subnet_id == "" ? 1 : 0

  vpc_id            = aws_vpc.nat_vpc[0].id
  cidr_block        = var.subnet_cidr_block
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "private-nat-subnet"
    pike = "permissions"
  }
}

locals {
  nat_gateway_subnet_id = var.existing_subnet_id != "" ? var.existing_subnet_id : aws_subnet.nat_subnet[0].id
}

resource "aws_nat_gateway" "private_nat_gateway" {
  subnet_id         = local.nat_gateway_subnet_id
  connectivity_type = "private"

  tags = {
    Name = "private-nat-gateway"
    pike = "permissions"
  }
}

output "nat_gateway_id" {
  description = "ID of the created Private NAT Gateway."
  value       = aws_nat_gateway.private_nat_gateway.id
}

output "nat_gateway_subnet_id" {
  description = "Subnet ID associated with the Private NAT Gateway."
  value       = local.nat_gateway_subnet_id
}

output "provided_elastic_ip_allocation_id" {
  description = "Elastic IP allocation ID provided as input. Not attached because Private NAT Gateways do not support Elastic IPs."
  value       = var.elastic_ip_allocation_id
}