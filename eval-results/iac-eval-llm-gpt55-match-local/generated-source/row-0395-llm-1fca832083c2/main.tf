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
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming."
  type        = string
  default     = "alb-forward-to-nlb"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

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

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnet_cidrs = [
    cidrsubnet(var.vpc_cidr, 8, 1),
    cidrsubnet(var.vpc_cidr, 8, 2)
  ]

  nlb_private_ips = [
    "10.0.1.50",
    "10.0.2.50"
  ]

  common_tags = {
    Project = var.project_name
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-${count.index + 1}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route" "public_default_ipv4" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for the public Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound HTTP to NLB private IPs"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = local.public_subnet_cidrs
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-alb-sg"
  })
}

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for backend EC2 instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP from inside the VPC, including ALB and NLB traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ec2-sg"
  })
}

resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_instance" "backend" {
  count = 2

  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public[count.index].id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y nginx
    systemctl enable nginx
    cat > /usr/share/nginx/html/index.html <<HTML
    <html>
      <body>
        <h1>Hello from backend instance ${count.index + 1}</h1>
        <p>Traffic path: ALB -> NLB -> EC2</p>
      </body>
    </html>
    HTML
    systemctl restart nginx
  EOF

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-backend-${count.index + 1}"
  })
}

resource "aws_lb" "application" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-alb"
  })
}

resource "aws_lb" "network" {
  name               = "${var.project_name}-nlb"
  load_balancer_type = "network"
  internal           = true

  dynamic "subnet_mapping" {
    for_each = {
      for idx, subnet in aws_subnet.public : idx => subnet
    }

    content {
      subnet_id            = subnet_mapping.value.id
      private_ipv4_address = local.nlb_private_ips[tonumber(subnet_mapping.key)]
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nlb"
  })
}

resource "aws_lb_target_group" "backend_instances" {
  name        = "${var.project_name}-ec2-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = "80"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ec2-tg"
  })
}

resource "aws_lb_target_group_attachment" "backend_instances" {
  count = 2

  target_group_arn = aws_lb_target_group.backend_instances.arn
  target_id        = aws_instance.backend[count.index].id
  port             = 80
}

resource "aws_lb_listener" "nlb_http" {
  load_balancer_arn = aws_lb.network.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_instances.arn
  }
}

resource "aws_lb_target_group" "nlb_ips" {
  name        = "${var.project_name}-nlb-ip-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/"
    matcher             = "200"
    port                = "80"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nlb-ip-tg"
  })
}

resource "aws_lb_target_group_attachment" "nlb_ips" {
  count = 2

  target_group_arn  = aws_lb_target_group.nlb_ips.arn
  target_id         = local.nlb_private_ips[count.index]
  port              = 80
  availability_zone = local.azs[count.index]

  depends_on = [
    aws_lb.network,
    aws_lb_listener.nlb_http
  ]
}

resource "aws_lb_listener" "alb_http" {
  load_balancer_arn = aws_lb.application.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_ips.arn
  }
}

output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer. Open this URL to test ALB -> NLB -> EC2."
  value       = aws_lb.application.dns_name
}

output "alb_url" {
  description = "Public HTTP URL for the Application Load Balancer."
  value       = "http://${aws_lb.application.dns_name}"
}

output "nlb_dns_name" {
  description = "Internal DNS name of the Network Load Balancer."
  value       = aws_lb.network.dns_name
}

output "nlb_private_ips" {
  description = "Static private IPs assigned to the Network Load Balancer and registered as ALB targets."
  value       = local.nlb_private_ips
}