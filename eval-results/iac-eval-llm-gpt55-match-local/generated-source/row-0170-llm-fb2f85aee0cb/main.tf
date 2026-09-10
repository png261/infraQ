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
  description = "AWS region where the DAX subnet group will be created."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.50.0.0/16"
}

variable "subnet_cidr_blocks" {
  description = "CIDR blocks for the private subnets used by the DAX subnet group."
  type        = list(string)
  default     = ["10.50.1.0/24", "10.50.2.0/24"]
}

variable "dax_subnet_group_name" {
  description = "Name of the custom DAX subnet group."
  type        = string
  default     = "custom-dax-subnet-group"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "dax_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "dax-subnet-group-vpc"
  }
}

resource "aws_subnet" "dax_private_subnets" {
  count = 2

  vpc_id                  = aws_vpc.dax_vpc.id
  cidr_block              = var.subnet_cidr_blocks[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "dax-private-subnet-${count.index + 1}"
  }
}

resource "aws_dax_subnet_group" "custom" {
  name        = var.dax_subnet_group_name
  description = "Custom subnet group for Amazon DAX clusters"
  subnet_ids  = aws_subnet.dax_private_subnets[*].id
}

output "dax_subnet_group_name" {
  description = "The name of the created DAX subnet group."
  value       = aws_dax_subnet_group.custom.name
}

output "dax_subnet_group_id" {
  description = "The ID of the created DAX subnet group."
  value       = aws_dax_subnet_group.custom.id
}

output "subnet_ids" {
  description = "Subnet IDs included in the DAX subnet group."
  value       = aws_subnet.dax_private_subnets[*].id
}

output "vpc_id" {
  description = "VPC ID containing the DAX subnet group subnets."
  value       = aws_vpc.dax_vpc.id
}