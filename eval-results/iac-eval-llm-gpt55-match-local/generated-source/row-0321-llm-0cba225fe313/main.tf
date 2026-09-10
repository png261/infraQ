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

############################################################
# Variables
############################################################

variable "aws_region" {
  description = "AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name used to prefix infrastructure resources."
  type        = string
  default     = "video-streaming-site"
}

variable "domain_name" {
  description = "Domain name for the Route53 hosted zone."
  type        = string
  default     = "example-video-streaming.com"
}

variable "record_name" {
  description = "DNS record name for the application."
  type        = string
  default     = "www"
}

variable "instance_type" {
  description = "EC2 instance type for video streaming servers."
  type        = string
  default     = "t3.micro"
}

variable "desired_capacity" {
  description = "Desired number of EC2 instances."
  type        = number
  default     = 3
}

variable "min_size" {
  description = "Minimum number of EC2 instances."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of EC2 instances."
  type        = number
  default     = 6
}

############################################################
# Availability Zones
############################################################

data "aws_availability_zones" "available" {
  state = "available"
}

############################################################
# VPC
############################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"

  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  public_subnets = [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24"
  ]

  enable_dns_hostnames = true
  enable_dns_support   = true

  map_public_ip_on_launch = true

  tags = {
    Project = var.project_name
  }
}

############################################################
# Latest Amazon Linux 2023 AMI
############################################################

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name = "name"
    values = [
      "al2023-ami-*-x86_64"
    ]
  }

  filter {
    name = "architecture"
    values = [
      "x86_64"
    ]
  }

  filter {
    name = "virtualization-type"
    values = [
      "hvm"
    ]
  }
}

############################################################
# IAM Role for EC2 Instances
############################################################

resource "aws_iam_role" "ec2_role" {
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

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

############################################################
# Security Groups
############################################################

resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP traffic from the internet to the load balancer."
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags = {
    Name    = "${var.project_name}-alb-sg"
    Project = var.project_name
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Allow HTTP traffic from the ALB to EC2 instances."
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Allow HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags = {
    Name    = "${var.project_name}-ec2-sg"
    Project = var.project_name
  }
}

############################################################
# Application Load Balancer
############################################################

resource "aws_lb" "app_alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false

  tags = {
    Name    = "${var.project_name}-alb"
    Project = var.project_name
  }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name    = "${var.project_name}-tg"
    Project = var.project_name
  }
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

############################################################
# EC2 Launch Template
############################################################

resource "aws_launch_template" "video_server" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }

  vpc_security_group_ids = [
    aws_security_group.ec2_sg.id
  ]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y nginx

    systemctl enable nginx
    systemctl start nginx

    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

    cat > /usr/share/nginx/html/index.html <<HTML
    <!DOCTYPE html>
    <html>
      <head>
        <title>Video Streaming Site</title>
        <style>
          body {
            font-family: Arial, sans-serif;
            background: #111827;
            color: #f9fafb;
            text-align: center;
            padding-top: 80px;
          }
          .box {
            background: #1f2937;
            display: inline-block;
            padding: 40px;
            border-radius: 12px;
          }
          video {
            width: 640px;
            max-width: 90%;
            margin-top: 20px;
            border: 2px solid #374151;
            border-radius: 8px;
          }
        </style>
      </head>
      <body>
        <div class="box">
          <h1>Video Streaming Site</h1>
          <p>Served by EC2 instance: $INSTANCE_ID</p>
          <p>Availability Zone: $AZ</p>
          <p>This server is behind an AWS Application Load Balancer.</p>
          <video controls>
            <source src="https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4" type="video/mp4">
            Your browser does not support the video tag.
          </video>
        </div>
      </body>
    </html>
    HTML
  EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name    = "${var.project_name}-server"
      Project = var.project_name
    }
  }

  tags = {
    Name    = "${var.project_name}-launch-template"
    Project = var.project_name
  }
}

############################################################
# Auto Scaling Group for Multiple Video Servers
############################################################

resource "aws_autoscaling_group" "video_servers" {
  name = "${var.project_name}-asg"

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  vpc_zone_identifier = module.vpc.public_subnets

  health_check_type         = "ELB"
  health_check_grace_period = 120

  target_group_arns = [
    aws_lb_target_group.app_tg.arn
  ]

  launch_template {
    id      = aws_launch_template.video_server.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-server"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_lb_listener.http_listener
  ]
}

############################################################
# Route53 DNS
############################################################

resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name    = var.domain_name
    Project = var.project_name
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.record_name}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.app_alb.dns_name
    zone_id                = aws_lb.app_alb.zone_id
    evaluate_target_health = true
  }
}

############################################################
# Optional Auto Scaling Policies
############################################################

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.project_name}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.video_servers.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 120
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.project_name}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.video_servers.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 120
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale out when average CPU is above 70 percent."
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.video_servers.name
  }
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "${var.project_name}-low-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "Scale in when average CPU is below 20 percent."
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.video_servers.name
  }
}

############################################################
# Outputs
############################################################

output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.app_alb.dns_name
}

output "route53_application_url" {
  description = "Application URL through Route53."
  value       = "http://${aws_route53_record.www.fqdn}"
}

output "route53_name_servers" {
  description = "Name servers for the Route53 hosted zone. Configure these at your domain registrar."
  value       = aws_route53_zone.main.name_servers
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = module.vpc.vpc_id
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group."
  value       = aws_autoscaling_group.video_servers.name
}