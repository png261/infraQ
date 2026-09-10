terraform {
  required_version = ">= 1.0"

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

resource "aws_vpc" "example" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "example-route53-association-vpc"
  }
}

resource "aws_route53_zone" "example" {
  name = "example.internal"

  vpc {
    vpc_id     = aws_vpc.example.id
    vpc_region = "us-east-1"
  }

  tags = {
    Name = "example-private-hosted-zone"
  }
}

resource "aws_route53_zone_association" "example" {
  zone_id    = aws_route53_zone.example.zone_id
  vpc_id     = aws_vpc.example.id
  vpc_region = "us-east-1"
}