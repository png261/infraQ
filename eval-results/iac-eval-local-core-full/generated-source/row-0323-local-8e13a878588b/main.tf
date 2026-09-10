data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "benchmark-vpc"
  }
}

resource "aws_subnet" "subnet_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "benchmark-subnet-1"
  }
}

resource "aws_subnet" "subnet_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "benchmark-subnet-2"
  }
}

resource "aws_security_group" "alb" {
  name        = "benchmark-alb-sg"
  description = "Allow HTTPS traffic for the benchmark ALB"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "benchmark-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "https_from_vpc" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = aws_vpc.main.cidr_block
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "https_to_anywhere" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_key_pair" "benchmark" {
  key_name   = "benchmark-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7Kx1v8XHhQpR3Q7fDcO1r5wXv0y1uE0kG7a9K6j8sLz6sQvG6qD3aK3pH6s1kJ5e7mP4c9nY2wR8tU1iO5pA7sD3fG5hJ7kL9zX2cV4bN6mQ8wE0rT2yU4iO6pA8sD0fG2hJ4kL6zX8cV0bN2mQ4wE6rT8yU0iO2pA4sD6fG8hJ0kL2zX4cV6bN8mQ0wE2rT4yU6iO8pA0sD2fG4hJ6kL8zX0cV2bN4mQ6wE8rT0yU2iO4pA6sD8fG0hJ2kL4zX6cV8bN0mQ2wE4rT6yU8iO0p benchmark@example"
}

resource "aws_instance" "app" {
  ami           = data.aws_ami.al2023.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.benchmark.key_name
  subnet_id     = aws_subnet.subnet_1.id

  tags = {
    Name = "benchmark-instance"
  }
}

resource "aws_lb" "app" {
  name               = "benchmark-app-lb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]

  tags = {
    Name = "benchmark-app-lb"
  }
}

resource "aws_lb_target_group" "app" {
  name     = "benchmark-app-tg"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.lb_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app.id
  port             = 443
}

resource "aws_route53_zone" "main" {
  name = "netflix.com"
}

resource "aws_route53_record" "lb_a" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "lb"
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "lb_aaaa" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "lb"
  type    = "AAAA"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}

resource "aws_s3_bucket" "video_content" {
  bucket = "video-content-bucket"
}
