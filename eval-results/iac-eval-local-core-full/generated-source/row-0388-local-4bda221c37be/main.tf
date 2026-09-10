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
    Name = "iac-eval-nlb-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "iac-eval-nlb-igw"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "iac-eval-nlb-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "iac-eval-nlb-public-rt"
  }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "instance" {
  name        = "iac-eval-nlb-instance-sg"
  description = "Allow inbound TCP traffic from the NLB target group port"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iac-eval-nlb-instance-sg"
  }
}

resource "aws_instance" "target" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.main.id
  vpc_security_group_ids      = [aws_security_group.instance.id]
  associate_public_ip_address = true

  tags = {
    Name = "iac-eval-nlb-target"
  }
}

resource "aws_lb" "network" {
  name               = "iac-eval-network-lb"
  load_balancer_type = "network"
  internal           = false
  subnets            = [aws_subnet.main.id]

  tags = {
    Name = "iac-eval-network-lb"
  }
}

resource "aws_lb_target_group" "instance" {
  name        = "iac-eval-nlb-tg"
  port        = 80
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled  = true
    port     = "traffic-port"
    protocol = "TCP"
  }

  tags = {
    Name = "iac-eval-nlb-tg"
  }
}

resource "aws_lb_target_group_attachment" "instance" {
  target_group_arn = aws_lb_target_group.instance.arn
  target_id        = aws_instance.target.id
  port             = 80
}

resource "aws_lb_listener" "tcp" {
  load_balancer_arn = aws_lb.network.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.instance.arn
  }
}
