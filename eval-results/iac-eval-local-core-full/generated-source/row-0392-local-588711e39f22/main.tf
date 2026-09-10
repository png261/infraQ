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
    Name = "iac-eval-nlb-eip-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "iac-eval-nlb-eip-igw"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "iac-eval-nlb-eip-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "iac-eval-nlb-eip-public-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "iac-eval-nlb-eip-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "instance" {
  name        = "iac-eval-nlb-eip-instance-sg"
  description = "Allow HTTP from the NLB benchmark listener and outbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP target traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iac-eval-nlb-eip-instance-sg"
  }
}

resource "aws_instance" "target" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.instance.id]
  associate_public_ip_address = true

  user_data = <<-EOT
    #!/bin/bash
    dnf install -y nginx
    systemctl enable --now nginx
    echo "iac-eval nlb target" > /usr/share/nginx/html/index.html
  EOT

  tags = {
    Name = "iac-eval-nlb-eip-target"
  }
}

resource "aws_eip" "nlb_a" {
  domain = "vpc"

  tags = {
    Name = "iac-eval-nlb-eip-a"
  }
}

resource "aws_eip" "nlb_b" {
  domain = "vpc"

  tags = {
    Name = "iac-eval-nlb-eip-b"
  }
}

resource "aws_lb" "network" {
  name               = "iac-eval-nlb-eip"
  load_balancer_type = "network"

  subnet_mapping {
    subnet_id     = aws_subnet.public_a.id
    allocation_id = aws_eip.nlb_a.id
  }

  subnet_mapping {
    subnet_id     = aws_subnet.public_b.id
    allocation_id = aws_eip.nlb_b.id
  }

  tags = {
    Name = "iac-eval-nlb-eip"
  }
}

resource "aws_lb_target_group" "http" {
  name     = "iac-eval-nlb-eip-tg"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled  = true
    port     = "traffic-port"
    protocol = "TCP"
  }
}

resource "aws_lb_target_group_attachment" "target" {
  target_group_arn = aws_lb_target_group.http.arn
  target_id        = aws_instance.target.id
  port             = 80
}

resource "aws_lb_listener" "tcp" {
  load_balancer_arn = aws_lb.network.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}
