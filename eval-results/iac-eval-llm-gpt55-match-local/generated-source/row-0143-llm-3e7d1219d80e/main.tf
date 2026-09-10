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
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_a_cidr_block" {
  description = "CIDR block for the subnet in us-east-1a"
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_b_cidr_block" {
  description = "CIDR block for the subnet in us-east-1b"
  type        = string
  default     = "10.0.2.0/24"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "redshift-vpc"
  }
}

resource "aws_subnet" "east_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_a_cidr_block
  availability_zone = "us-east-1a"

  tags = {
    Name = "redshift-subnet-us-east-1a"
  }
}

resource "aws_subnet" "east_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_b_cidr_block
  availability_zone = "us-east-1b"

  tags = {
    Name = "redshift-subnet-us-east-1b"
  }
}

resource "aws_redshift_subnet_group" "main" {
  name        = "redshift-subnet-group"
  description = "Redshift subnet group with subnets in us-east-1a and us-east-1b"

  subnet_ids = [
    aws_subnet.east_1a.id,
    aws_subnet.east_1b.id
  ]

  tags = {
    Name = "redshift-subnet-group"
  }
}