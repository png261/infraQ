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
  region = "us-east-1"
}

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "iac-eval-nat-gateway-vpc"
  }
}

resource "aws_subnet" "nat" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "iac-eval-nat-gateway-subnet"
  }
}

resource "aws_nat_gateway" "this" {
  connectivity_type = "private"
  subnet_id         = aws_subnet.nat.id

  tags = {
    pike = "permissions"
  }
}
