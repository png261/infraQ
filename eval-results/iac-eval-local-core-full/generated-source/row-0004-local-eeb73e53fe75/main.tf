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
    Name = "main"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "private-b"
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "main"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "main"
  }
}

resource "aws_route53_zone" "public" {
  name = "public"
}

resource "aws_route53_zone" "private" {
  name = "private"

  vpc {
    vpc_id = aws_vpc.main.id
  }
}

resource "aws_db_instance" "internal" {
  identifier           = "internal"
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t3.micro"
  username             = "adminuser"
  password             = "InternalPass123!"
  db_subnet_group_name = aws_db_subnet_group.main.name
  skip_final_snapshot  = true
}

resource "aws_db_instance" "public" {
  identifier           = "public"
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t3.micro"
  username             = "adminuser"
  password             = "PublicPass123!"
  db_subnet_group_name = aws_db_subnet_group.main.name
  publicly_accessible  = true
  skip_final_snapshot  = true
}

resource "aws_route53_record" "internal_db" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "db.private"
  type    = "CNAME"
  ttl     = 300
  records = [aws_db_instance.internal.address]
}

resource "aws_route53_record" "public_db" {
  zone_id = aws_route53_zone.public.zone_id
  name    = "db.public"
  type    = "CNAME"
  ttl     = 300
  records = [aws_db_instance.public.address]
}
