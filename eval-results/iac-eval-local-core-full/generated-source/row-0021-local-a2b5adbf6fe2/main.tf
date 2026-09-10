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

resource "aws_route53_zone" "example" {
  name = "example53.com"
}

resource "aws_route53_record" "ipv6" {
  zone_id = aws_route53_zone.example.zone_id
  name    = "www.example53.com"
  type    = "AAAA"
  ttl     = 300
  records = ["2001:db8::1"]
}
