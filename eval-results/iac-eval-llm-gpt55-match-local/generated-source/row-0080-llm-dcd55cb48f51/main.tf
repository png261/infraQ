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

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main"
  }
}

resource "aws_route53_zone" "private_zone" {
  name = "internal.example53.com"

  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = {
    Name = "internal.example53.com"
  }
}

resource "aws_route53_record" "internal_record" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "app.internal.example53.com"
  type    = "A"
  ttl     = 300

  records = [
    "10.0.1.10"
  ]
}