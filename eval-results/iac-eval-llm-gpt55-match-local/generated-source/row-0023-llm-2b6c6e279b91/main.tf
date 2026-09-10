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

resource "aws_route53_zone" "example" {
  name = "example"

  comment = "Hosted zone for domain ownership verification"
}

resource "aws_route53_record" "domain_verification" {
  zone_id = aws_route53_zone.example.zone_id
  name    = aws_route53_zone.example.name
  type    = "TXT"
  ttl     = 300

  records = [
    "\"passwordpassword\""
  ]
}