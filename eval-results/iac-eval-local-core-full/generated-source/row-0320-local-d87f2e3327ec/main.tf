resource "aws_vpc" "streaming" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "video-streaming-vpc"
  }
}

resource "aws_internet_gateway" "streaming" {
  vpc_id = aws_vpc.streaming.id

  tags = {
    Name = "video-streaming-igw"
  }
}

resource "aws_subnet" "streaming_a" {
  vpc_id                  = aws_vpc.streaming.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "video-streaming-subnet-a"
  }
}

resource "aws_subnet" "streaming_b" {
  vpc_id                  = aws_vpc.streaming.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "video-streaming-subnet-b"
  }
}

resource "aws_route_table" "streaming_public" {
  vpc_id = aws_vpc.streaming.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.streaming.id
  }

  tags = {
    Name = "video-streaming-public-rt"
  }
}

resource "aws_route_table_association" "streaming_a" {
  subnet_id      = aws_subnet.streaming_a.id
  route_table_id = aws_route_table.streaming_public.id
}

resource "aws_route_table_association" "streaming_b" {
  subnet_id      = aws_subnet.streaming_b.id
  route_table_id = aws_route_table.streaming_public.id
}

resource "aws_security_group" "streaming" {
  name        = "video-streaming-sg"
  description = "Allow HTTP traffic for the video streaming benchmark stack"
  vpc_id      = aws_vpc.streaming.id

  ingress {
    description = "HTTP from the internet"
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
    Name = "video-streaming-sg"
  }
}

resource "aws_s3_bucket" "streaming_assets" {
  bucket_prefix = "video-streaming-assets-"

  tags = {
    Name = "video-streaming-assets"
  }
}

data "aws_ami" "amazon_linux" {
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

resource "aws_instance" "streaming" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.streaming_a.id
  vpc_security_group_ids      = [aws_security_group.streaming.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y httpd
    systemctl enable --now httpd
    echo "video streaming server" > /var/www/html/index.html
  EOF

  tags = {
    Name = "video-streaming-server"
  }
}

resource "aws_lb" "streaming" {
  name               = "video-streaming-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = [aws_subnet.streaming_a.id, aws_subnet.streaming_b.id]
  security_groups    = [aws_security_group.streaming.id]

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
    enabled = true
    path    = "/"
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

resource "aws_lb_listener" "streaming" {
  load_balancer_arn = aws_lb.streaming.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.streaming.arn
  }
}
