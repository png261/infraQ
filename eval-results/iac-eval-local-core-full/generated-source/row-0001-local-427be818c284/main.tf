resource "aws_vpc" "primary" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "route53-primary-vpc"
  }
}

resource "aws_vpc" "associated" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "route53-associated-vpc"
  }
}

resource "aws_route53_zone" "private" {
  name = "example.internal"

  vpc {
    vpc_id = aws_vpc.primary.id
  }
}

resource "aws_route53_vpc_association_authorization" "associated" {
  vpc_id  = aws_vpc.associated.id
  zone_id = aws_route53_zone.private.zone_id
}

resource "aws_route53_zone_association" "associated" {
  vpc_id  = aws_route53_vpc_association_authorization.associated.vpc_id
  zone_id = aws_route53_vpc_association_authorization.associated.zone_id
}
