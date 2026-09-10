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
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "gateway-load-balancer-demo"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidrs" {
  description = "CIDR blocks for Gateway Load Balancer subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "gwlb" {
  count = length(var.subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-gwlb-subnet-${count.index + 1}"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-route-table"
  }
}

resource "aws_route" "default_internet_route" {
  route_table_id         = aws_route_table.main.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "gwlb" {
  count = length(aws_subnet.gwlb)

  subnet_id      = aws_subnet.gwlb[count.index].id
  route_table_id = aws_route_table.main.id
}

resource "aws_lb" "gateway" {
  name               = "${var.project_name}-gwlb"
  load_balancer_type = "gateway"
  subnets            = aws_subnet.gwlb[*].id

  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.project_name}-gwlb"
  }
}

resource "aws_lb_target_group" "gateway" {
  name        = "${var.project_name}-tg"
  port        = 6081
  protocol    = "GENEVE"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-gwlb-tg"
  }
}

resource "aws_lb_listener" "gateway" {
  load_balancer_arn = aws_lb.gateway.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "gateway_load_balancer_arn" {
  description = "ARN of the Gateway Load Balancer."
  value       = aws_lb.gateway.arn
}

output "gateway_load_balancer_dns_name" {
  description = "DNS name of the Gateway Load Balancer."
  value       = aws_lb.gateway.dns_name
}

output "gateway_load_balancer_zone_id" {
  description = "Canonical hosted zone ID of the Gateway Load Balancer."
  value       = aws_lb.gateway.zone_id
}

output "gateway_target_group_arn" {
  description = "ARN of the Gateway Load Balancer target group."
  value       = aws_lb_target_group.gateway.arn
}