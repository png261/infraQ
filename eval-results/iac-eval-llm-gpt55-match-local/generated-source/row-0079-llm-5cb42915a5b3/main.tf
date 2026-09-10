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

resource "aws_route53_zone" "example53_com" {
  name = "example53.com"
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.example53_com.zone_id
  name    = "www.example53.com"
  type    = "A"
  ttl     = 300

  records = [
    "192.0.2.10"
  ]
}