terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

variable "domain_name" {
  description = "The domain name for the Route 53 hosted zone."
  type        = string
  default     = "example.com"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "route53-elb-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "route53-elb-igw"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "route53-elb-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "route53-elb-public-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "route53-elb-public-rt"
  }
}

resource "aws_route" "default_ipv4" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "elb" {
  name        = "route53-elb-main-sg"
  description = "Security group for the main ELB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound IPv4 traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "route53-elb-main-sg"
  }
}

resource "aws_elb" "main" {
  name            = "main-elb"
  subnets         = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  security_groups = [aws_security_group.elb.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  cross_zone_load_balancing = true
  idle_timeout              = 60
  connection_draining       = true
  connection_draining_timeout = 300

  tags = {
    Name = "main"
  }
}

resource "aws_route53_zone" "primary" {
  name = var.domain_name

  tags = {
    Name = "primary"
  }
}

resource "aws_route53_record" "elb_alias" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = aws_route53_zone.primary.name
  type    = "A"

  alias {
    name                   = aws_elb.main.dns_name
    zone_id                = aws_elb.main.zone_id
    evaluate_target_health = false
  }
}

output "route53_zone_id" {
  description = "The Route 53 hosted zone ID."
  value       = aws_route53_zone.primary.zone_id
}

output "elb_dns_name" {
  description = "The DNS name of the Elastic Load Balancer."
  value       = aws_elb.main.dns_name
}

output "alias_record_fqdn" {
  description = "The fully qualified domain name of the Route 53 alias record."
  value       = aws_route53_record.elb_alias.fqdn
}