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
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_1_cidr" {
  description = "CIDR block for the first private subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_2_cidr" {
  description = "CIDR block for the second private subnet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "nlb_private_ip_1" {
  description = "Static private IPv4 address for the NLB in the first private subnet."
  type        = string
  default     = "10.0.1.50"
}

variable "nlb_private_ip_2" {
  description = "Static private IPv4 address for the NLB in the second private subnet."
  type        = string
  default     = "10.0.2.50"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "internal-nlb-vpc"
  }
}

resource "aws_subnet" "private_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_1_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "internal-nlb-private-subnet-1"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_2_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "internal-nlb-private-subnet-2"
  }
}

resource "aws_lb" "internal_nlb" {
  name               = "static-private-ip-internal-nlb"
  internal           = true
  load_balancer_type = "network"

  subnet_mapping {
    subnet_id            = aws_subnet.private_1.id
    private_ipv4_address = var.nlb_private_ip_1
  }

  subnet_mapping {
    subnet_id            = aws_subnet.private_2.id
    private_ipv4_address = var.nlb_private_ip_2
  }

  enable_deletion_protection = false

  tags = {
    Name = "static-private-ip-internal-nlb"
  }
}

resource "aws_lb_target_group" "tcp_targets" {
  name        = "internal-nlb-tcp-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    protocol            = "TCP"
    port                = "80"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = {
    Name = "internal-nlb-tcp-target-group"
  }
}

resource "aws_lb_listener" "tcp_80" {
  load_balancer_arn = aws_lb.internal_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tcp_targets.arn
  }
}

output "internal_nlb_dns_name" {
  description = "DNS name of the internal Network Load Balancer."
  value       = aws_lb.internal_nlb.dns_name
}

output "internal_nlb_arn" {
  description = "ARN of the internal Network Load Balancer."
  value       = aws_lb.internal_nlb.arn
}

output "nlb_private_ip_addresses" {
  description = "Static private IP addresses assigned to the internal NLB."
  value = [
    var.nlb_private_ip_1,
    var.nlb_private_ip_2
  ]
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets used by the internal NLB."
  value = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id
  ]
}