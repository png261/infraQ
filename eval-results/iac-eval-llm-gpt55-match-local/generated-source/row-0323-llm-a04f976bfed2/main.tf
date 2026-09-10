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

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "domain_name" {
  description = "Route53 hosted zone domain name."
  type        = string
  default     = "test-video-stream.com"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "latest_ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "test-video-stream-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "test-video-stream-igw"
  }
}

resource "aws_subnet" "subnet_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "test-video-stream-subnet-1"
  }
}

resource "aws_subnet" "subnet_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.5.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "test-video-stream-subnet-2"
  }
}

resource "aws_subnet" "subnet_3" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.6.0/24"
  availability_zone       = data.aws_availability_zones.available.names[2]
  map_public_ip_on_launch = true

  tags = {
    Name = "test-video-stream-subnet-3"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "test-video-stream-public-rt"
  }
}

resource "aws_route_table_association" "subnet_1" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "subnet_2" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "subnet_3" {
  subnet_id      = aws_subnet.subnet_3.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "lb_sg" {
  name        = "test-video-stream-lb-sg"
  description = "Security group for ALB and target instance"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "test-video-stream-lb-sg"
  }
}

resource "aws_security_group_rule" "ingress_http_from_vpc" {
  type              = "ingress"
  description       = "Allow HTTP ingress from VPC CIDR"
  security_group_id = aws_security_group.lb_sg.id

  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = [aws_vpc.main.cidr_block]
}

resource "aws_security_group_rule" "egress_http_anywhere" {
  type              = "egress"
  description       = "Allow HTTP egress to any IPv4 address"
  security_group_id = aws_security_group.lb_sg.id

  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_lb" "application" {
  name               = "test-video-stream-alb"
  load_balancer_type = "application"
  internal           = false

  security_groups = [
    aws_security_group.lb_sg.id
  ]

  subnets = [
    aws_subnet.subnet_1.id,
    aws_subnet.subnet_2.id,
    aws_subnet.subnet_3.id
  ]

  tags = {
    Name = "test-video-stream-alb"
  }
}

resource "aws_lb_target_group" "http" {
  name     = "test-video-stream-tg"
  vpc_id   = aws_vpc.main.id
  port     = 80
  protocol = "HTTP"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/"
    matcher             = "200"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
  }

  tags = {
    Name = "test-video-stream-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.application.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}

resource "aws_instance" "ubuntu_web" {
  ami                         = data.aws_ami.latest_ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.subnet_1.id
  vpc_security_group_ids      = [aws_security_group.lb_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    mkdir -p /var/www/html
    echo "Hello from Ubuntu behind the Application Load Balancer" > /var/www/html/index.html
    cd /var/www/html
    nohup python3 -m http.server 80 --bind 0.0.0.0 > /var/log/python-http-server.log 2>&1 &
  EOF

  tags = {
    Name = "test-video-stream-ubuntu-web"
  }
}

resource "aws_lb_target_group_attachment" "ubuntu_web" {
  target_group_arn = aws_lb_target_group.http.arn
  target_id        = aws_instance.ubuntu_web.id
  port             = 80
}

resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name = "test-video-stream-zone"
  }
}

resource "aws_route53_record" "lb_ipv4" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "lb.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.application.dns_name
    zone_id                = aws_lb.application.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "lb_ipv6" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "lb.${var.domain_name}"
  type    = "AAAA"

  alias {
    name                   = aws_lb.application.dns_name
    zone_id                = aws_lb.application.zone_id
    evaluate_target_health = true
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "load_balancer_dns_name" {
  value = aws_lb.application.dns_name
}

output "route53_zone_name_servers" {
  value = aws_route53_zone.main.name_servers
}

output "lb_alias_ipv4_record" {
  value = aws_route53_record.lb_ipv4.fqdn
}

output "lb_alias_ipv6_record" {
  value = aws_route53_record.lb_ipv6.fqdn
}