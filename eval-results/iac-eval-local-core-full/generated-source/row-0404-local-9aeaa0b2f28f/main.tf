data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
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
    Name = "iac-eval-alb-target-vpc"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "iac-eval-alb-target-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "iac-eval-alb-target-private-b"
  }
}

resource "aws_lb" "main" {
  name               = "iac-eval-main-alb"
  internal           = true
  load_balancer_type = "application"
  subnets            = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "iac-eval-main-alb"
  }
}

resource "aws_lb_target_group" "alb_target" {
  name        = "iac-eval-alb-target-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "alb"

  health_check {
    path     = "/"
    protocol = "HTTP"
    matcher  = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "main_alb" {
  target_group_arn = aws_lb_target_group.alb_target.arn
  target_id        = aws_lb.main.arn
  port             = 80
}

resource "aws_lb_listener" "main_http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "OK"
      status_code  = "200"
    }
  }
}

resource "aws_instance" "example" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.private_a.id

  tags = {
    Name = "iac-eval-example-instance"
  }
}
