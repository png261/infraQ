data "aws_availability_zones" "available" {
  state = "available"
}

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

resource "aws_vpc" "streaming" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "video-streaming-vpc"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.streaming.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "video-streaming-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.streaming.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "video-streaming-public-b"
  }
}

resource "aws_internet_gateway" "streaming" {
  vpc_id = aws_vpc.streaming.id

  tags = {
    Name = "video-streaming-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.streaming.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.streaming.id
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
  description = "Allow HTTP traffic for the video streaming load balancer and server"
  vpc_id      = aws_vpc.streaming.id

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

resource "aws_instance" "streaming" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y httpd
    systemctl enable --now httpd
    echo "Video streaming server" > /var/www/html/index.html
  EOF

  tags = {
    Name = "video-streaming-server"
  }
}

resource "aws_lb" "streaming" {
  name               = "video-streaming-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  security_groups    = [aws_security_group.web.id]

  tags = {
    Name = "video-streaming-alb"
  }
}

resource "aws_lb_target_group" "streaming" {
  name     = "video-streaming-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.streaming.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "video-streaming-tg"
  }
}

resource "aws_lb_target_group_attachment" "streaming" {
  target_group_arn = aws_lb_target_group.streaming.arn
  target_id        = aws_instance.streaming.id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.streaming.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.streaming.arn
  }
}

resource "aws_route53_zone" "streaming" {
  name = "video-streaming.example.com"
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.streaming.zone_id
  name    = "www.video-streaming.example.com"
  type    = "A"

  alias {
    name                   = aws_lb.streaming.dns_name
    zone_id                = aws_lb.streaming.zone_id
    evaluate_target_health = true
  }
}

resource "aws_s3_bucket" "videos" {
  bucket_prefix = "video-streaming-assets-"

  tags = {
    Name = "video-streaming-assets"
  }
}
