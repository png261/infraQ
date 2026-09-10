data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "video" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "video-streaming-vpc"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.video.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "video-streaming-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.video.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "video-streaming-public-b"
  }
}

resource "aws_internet_gateway" "video" {
  vpc_id = aws_vpc.video.id

  tags = {
    Name = "video-streaming-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.video.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.video.id
  }

  tags = {
    Name = "video-streaming-public-rt"
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

resource "aws_security_group" "web" {
  name        = "video-streaming-web-sg"
  description = "Allow HTTP traffic for video streaming demo"
  vpc_id      = aws_vpc.video.id

  ingress {
    description = "HTTP from internet"
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
    Name = "video-streaming-web-sg"
  }
}

resource "aws_instance" "video" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true

  user_data = <<-EOT
    #!/bin/bash
    dnf install -y nginx
    systemctl enable --now nginx
    echo "video streaming demo" > /usr/share/nginx/html/index.html
  EOT

  tags = {
    Name = "video-streaming-server"
  }
}

resource "aws_lb" "video" {
  name               = "video-streaming-lb"
  load_balancer_type = "application"
  internal           = false
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  security_groups    = [aws_security_group.web.id]

  tags = {
    Name = "video-streaming-lb"
  }
}

resource "aws_lb_target_group" "video" {
  name     = "video-streaming-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.video.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "video-streaming-tg"
  }
}

resource "aws_lb_target_group_attachment" "video" {
  target_group_arn = aws_lb_target_group.video.arn
  target_id        = aws_instance.video.id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.video.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.video.arn
  }
}

resource "aws_route53_zone" "video" {
  name = "video-streaming.example.com"
}

resource "aws_route53_record" "video" {
  zone_id = aws_route53_zone.video.zone_id
  name    = "www.video-streaming.example.com"
  type    = "A"

  alias {
    name                   = aws_lb.video.dns_name
    zone_id                = aws_lb.video.zone_id
    evaluate_target_health = true
  }
}

resource "aws_s3_bucket" "video" {
  bucket_prefix = "video-streaming-assets-"

  tags = {
    Name = "video-streaming-assets"
  }
}
