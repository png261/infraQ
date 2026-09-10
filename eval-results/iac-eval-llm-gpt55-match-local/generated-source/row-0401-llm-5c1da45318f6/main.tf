terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "load_balancer_name" {
  description = "Name of the Application Load Balancer."
  type        = string
  default     = "example-alb"
}

variable "target_group_name" {
  description = "Name of the target group."
  type        = string
  default     = "example-target-group"
}

variable "target_group_port" {
  description = "Port on which targets receive traffic."
  type        = number
  default     = 80
}

variable "target_group_protocol" {
  description = "Protocol used by the target group."
  type        = string
  default     = "HTTP"
}

provider "aws" {
  region = var.aws_region
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

resource "aws_security_group" "alb_sg" {
  name        = "example-alb-security-group"
  description = "Security group for the Application Load Balancer"
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

  tags = {
    Name = "example-alb-security-group"
  }
}

resource "aws_lb" "application_lb" {
  name               = var.load_balancer_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids

  enable_deletion_protection = false

  tags = {
    Name = var.load_balancer_name
  }
}

resource "aws_lb_target_group" "http_tg" {
  name        = var.target_group_name
  port        = var.target_group_port
  protocol    = var.target_group_protocol
  vpc_id      = data.aws_vpc.default.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    protocol            = "HTTP"
  }

  tags = {
    Name = var.target_group_name
  }
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.application_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http_tg.arn
  }
}

output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.application_lb.dns_name
}

output "load_balancer_arn" {
  description = "ARN of the Application Load Balancer."
  value       = aws_lb.application_lb.arn
}

output "target_group_arn" {
  description = "ARN of the target group."
  value       = aws_lb_target_group.http_tg.arn
}