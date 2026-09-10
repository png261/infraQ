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
  default     = "10.0.0.0/16"
}

variable "subnet_cidr_blocks" {
  description = "CIDR blocks for the DAX private subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "dax_subnet_group_name" {
  description = "Name of the DAX subnet group."
  type        = string
  default     = "example-dax-subnet-group"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "dax_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "dax-vpc"
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

resource "aws_dax_subnet_group" "example" {
  name        = var.dax_subnet_group_name
  description = "Subnet group for Amazon DAX cluster"
  subnet_ids  = aws_subnet.dax_private_subnets[*].id
}

output "dax_subnet_group_name" {
  description = "The name of the created DAX subnet group."
  value       = aws_dax_subnet_group.example.name
}

output "dax_subnet_group_id" {
  description = "The ID of the created DAX subnet group."
  value       = aws_dax_subnet_group.example.id
}

output "vpc_id" {
  description = "The ID of the VPC created for the DAX subnet group."
  value       = aws_vpc.dax_vpc.id
}

output "subnet_ids" {
  description = "Subnet IDs included in the DAX subnet group."
  value       = aws_subnet.dax_private_subnets[*].id
}