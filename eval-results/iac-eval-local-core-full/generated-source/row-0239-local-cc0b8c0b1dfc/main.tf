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

resource "aws_vpc" "benchmark" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "benchmark-vpc"
  }
}

resource "aws_internet_gateway" "benchmark" {
  vpc_id = aws_vpc.benchmark.id

  tags = {
    Name = "benchmark-igw"
  }
}

resource "aws_route_table" "benchmark" {
  vpc_id = aws_vpc.benchmark.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.benchmark.id
  }

  tags = {
    Name = "benchmark-route-table"
  }
}
