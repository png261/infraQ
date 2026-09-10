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

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "redshift-benchmark-vpc"
  }
}

resource "aws_subnet" "east_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "redshift-benchmark-east-1a"
  }
}

resource "aws_subnet" "east_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "redshift-benchmark-east-1b"
  }
}

resource "aws_redshift_subnet_group" "main" {
  name       = "redshift-benchmark-subnet-group"
  subnet_ids = [aws_subnet.east_1a.id, aws_subnet.east_1b.id]

  tags = {
    Name = "redshift-benchmark-subnet-group"
  }
}
