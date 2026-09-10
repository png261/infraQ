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

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "iac-eval-gwlb-vpc"
  }
}

resource "aws_subnet" "gwlb_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "iac-eval-gwlb-subnet-a"
  }
}

resource "aws_subnet" "gwlb_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "iac-eval-gwlb-subnet-b"
  }
}

resource "aws_security_group" "appliance" {
  name        = "iac-eval-gwlb-appliance"
  description = "Allow Geneve traffic for the Gateway Load Balancer target"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Geneve from VPC"
    from_port   = 6081
    to_port     = 6081
    protocol    = "udp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iac-eval-gwlb-appliance-sg"
  }
}

resource "aws_instance" "appliance" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.gwlb_a.id
  vpc_security_group_ids = [aws_security_group.appliance.id]

  tags = {
    Name = "iac-eval-gwlb-appliance"
  }
}

resource "aws_lb" "gateway" {
  name               = "iac-eval-gwlb"
  load_balancer_type = "gateway"
  subnets            = [aws_subnet.gwlb_a.id, aws_subnet.gwlb_b.id]

  tags = {
    Name = "iac-eval-gwlb"
  }
}

resource "aws_lb_target_group" "gateway" {
  name        = "iac-eval-gwlb-tg"
  port        = 6081
  protocol    = "GENEVE"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    protocol = "TCP"
    port     = "80"
  }

  tags = {
    Name = "iac-eval-gwlb-tg"
  }
}

resource "aws_lb_listener" "gateway" {
  load_balancer_arn = aws_lb.gateway.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }
}

resource "aws_lb_target_group_attachment" "appliance" {
  target_group_arn = aws_lb_target_group.gateway.arn
  target_id        = aws_instance.appliance.id
  port             = 6081
}
