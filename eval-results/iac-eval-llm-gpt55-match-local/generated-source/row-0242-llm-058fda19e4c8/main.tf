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
  description = "AWS region to deploy the Neptune subnet group resources into."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the example VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_one_cidr_block" {
  description = "CIDR block for the first Neptune subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_two_cidr_block" {
  description = "CIDR block for the second Neptune subnet."
  type        = string
  default     = "10.0.2.0/24"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "example" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "example-neptune-vpc"
  }
}

resource "aws_subnet" "neptune_subnet_one" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = var.subnet_one_cidr_block
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "example-neptune-subnet-1"
  }
}

resource "aws_subnet" "neptune_subnet_two" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = var.subnet_two_cidr_block
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "example-neptune-subnet-2"
  }
}

resource "aws_neptune_subnet_group" "example" {
  name        = "example-neptune-subnet-group"
  description = "Example subnet group for an Amazon Neptune cluster"

  subnet_ids = [
    aws_subnet.neptune_subnet_one.id,
    aws_subnet.neptune_subnet_two.id
  ]

  tags = {
    Name = "example-neptune-subnet-group"
  }
}

output "vpc_id" {
  description = "ID of the VPC created for Neptune."
  value       = aws_vpc.example.id
}

output "neptune_subnet_ids" {
  description = "Subnet IDs included in the Neptune subnet group."
  value = [
    aws_subnet.neptune_subnet_one.id,
    aws_subnet.neptune_subnet_two.id
  ]
}

output "neptune_subnet_group_name" {
  description = "Name of the Neptune subnet group."
  value       = aws_neptune_subnet_group.example.name
}