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
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "zone_name" {
  description = "The DNS name for the Route 53 hosted zone."
  type        = string
  default     = "example.com"
}

variable "record_name" {
  description = "The DNS record name to point to the ELB."
  type        = string
  default     = "www"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "elb" {
  name        = "main-elb-sg"
  description = "Security group for the main ELB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow HTTP inbound traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elb" "main" {
  name            = "main"
  subnets         = data.aws_subnets.default.ids
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
  name = var.zone_name

  tags = {
    Name = "primary"
  }
}

resource "aws_route53_record" "elb_alias" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "${var.record_name}.${aws_route53_zone.primary.name}"
  type    = "A"

  alias {
    name                   = aws_elb.main.dns_name
    zone_id                = aws_elb.main.zone_id
    evaluate_target_health = true
  }
}