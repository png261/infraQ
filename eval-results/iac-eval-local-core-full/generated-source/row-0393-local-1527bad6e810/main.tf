data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
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

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "iac-eval-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "iac-eval-private-b"
  }
}

resource "aws_security_group" "instance" {
  name        = "iac-eval-instance-sg"
  description = "Allow HTTP from within the VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow all outbound IPv4"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iac-eval-instance-sg"
  }
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_a.id
  vpc_security_group_ids      = [aws_security_group.instance.id]
  associate_public_ip_address = false

  tags = {
    Name = "iac-eval-nlb-target"
  }
}

resource "aws_eip" "reserved" {
  domain = "vpc"

  tags = {
    Name = "iac-eval-reserved-eip"
  }
}

resource "aws_lb" "internal" {
  name               = "iac-eval-internal-nlb"
  internal           = true
  load_balancer_type = "network"

  subnet_mapping {
    subnet_id            = aws_subnet.private_a.id
    private_ipv4_address = "10.0.1.10"
  }

  subnet_mapping {
    subnet_id            = aws_subnet.private_b.id
    private_ipv4_address = "10.0.2.10"
  }

  tags = {
    Name = "iac-eval-internal-nlb"
  }
}

resource "aws_lb_target_group" "app" {
  name        = "iac-eval-app-tg"
  port        = 80
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id
}

resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app.id
  port             = 80
}

resource "aws_lb_listener" "tcp" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
