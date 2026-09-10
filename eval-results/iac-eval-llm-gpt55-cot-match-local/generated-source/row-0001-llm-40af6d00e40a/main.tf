terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_vpc" "example" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "route53-association-vpc-${random_id.suffix.hex}"
  }
}

resource "aws_route53_zone" "private" {
  name = "example-${random_id.suffix.hex}.internal"

  vpc {
    vpc_id = aws_vpc.example.id
  }

  comment = "Private hosted zone for Route 53 zone association example"

  tags = {
    Name = "example-private-zone-${random_id.suffix.hex}"
  }
}

resource "aws_vpc" "associated" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "route53-associated-vpc-${random_id.suffix.hex}"
  }
}

resource "aws_route53_zone_association" "example" {
  zone_id = aws_route53_zone.private.zone_id
  vpc_id  = aws_vpc.associated.id
}