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
  description = "AWS region where the load balancer will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_1_cidr" {
  description = "CIDR block for the first public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_2_cidr" {
  description = "CIDR block for the second public subnet."
  type        = string
  default     = "10.0.2.0/24"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "eip-nlb-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "eip-nlb-igw"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "eip-nlb-public-subnet-1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "eip-nlb-public-subnet-2"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "eip-nlb-public-route-table"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nlb_1" {
  domain = "vpc"

  tags = {
    Name = "eip-nlb-address-1"
  }
}

resource "aws_eip" "nlb_2" {
  domain = "vpc"

  tags = {
    Name = "eip-nlb-address-2"
  }
}

resource "aws_lb" "network" {
  name               = "eip-network-load-balancer"
  load_balancer_type = "network"
  internal           = false

  subnet_mapping {
    subnet_id     = aws_subnet.public_1.id
    allocation_id = aws_eip.nlb_1.id
  }

  subnet_mapping {
    subnet_id     = aws_subnet.public_2.id
    allocation_id = aws_eip.nlb_2.id
  }

  enable_deletion_protection = false

  tags = {
    Name = "eip-network-load-balancer"
  }
}

resource "aws_lb_target_group" "tcp" {
  name        = "eip-nlb-tcp-target-group"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = {
    Name = "eip-nlb-tcp-target-group"
  }
}

resource "aws_lb_listener" "tcp_80" {
  load_balancer_arn = aws_lb.network.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tcp.arn
  }
}

output "load_balancer_dns_name" {
  description = "DNS name of the Network Load Balancer."
  value       = aws_lb.network.dns_name
}

output "load_balancer_zone_id" {
  description = "Canonical hosted zone ID of the Network Load Balancer."
  value       = aws_lb.network.zone_id
}

output "elastic_ip_1" {
  description = "First Elastic IP address assigned to the Network Load Balancer."
  value       = aws_eip.nlb_1.public_ip
}

output "elastic_ip_2" {
  description = "Second Elastic IP address assigned to the Network Load Balancer."
  value       = aws_eip.nlb_2.public_ip
}