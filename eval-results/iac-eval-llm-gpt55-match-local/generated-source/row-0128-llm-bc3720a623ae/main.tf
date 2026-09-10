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

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "instance_type" {
  description = "Instance type used by the EC2 Fleet."
  type        = string
  default     = "t3.micro"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "ec2-fleet-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "ec2-fleet-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "ec2-fleet-public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "ec2-fleet-private-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "ec2-fleet-public-rt"
  }
}

resource "aws_route" "public_default_ipv4" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "ec2-fleet-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "ec2_fleet" {
  name        = "ec2-fleet-sg"
  description = "Security group for EC2 Fleet instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow SSH from anywhere. Restrict this in production."
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow ICMP within the VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow all outbound IPv4 traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-fleet-sg"
  }
}

resource "aws_iam_role" "ec2_instance_role" {
  name = "ec2-fleet-instance-role"

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
    Name = "ec2-fleet-instance-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-fleet-instance-profile"
  role = aws_iam_role.ec2_instance_role.name
}

resource "aws_iam_service_linked_role" "ec2_fleet" {
  aws_service_name = "ec2fleet.amazonaws.com"
  description      = "Service-linked role for EC2 Fleet"

  lifecycle {
    ignore_changes = [
      description
    ]
  }
}

resource "aws_iam_service_linked_role" "spot" {
  aws_service_name = "spot.amazonaws.com"
  description      = "Service-linked role for EC2 Spot Instances"

  lifecycle {
    ignore_changes = [
      description
    ]
  }
}

resource "aws_launch_template" "ec2_fleet" {
  name_prefix   = "amazon-linux-2-ec2-fleet-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type

  update_default_version = true

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }

  vpc_security_group_ids = [
    aws_security_group.ec2_fleet.id
  ]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "ec2-fleet-amazon-linux-2"
    }
  }

  tag_specifications {
    resource_type = "volume"

    tags = {
      Name = "ec2-fleet-amazon-linux-2-volume"
    }
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF
  )

  tags = {
    Name = "ec2-fleet-launch-template"
  }
}

resource "aws_ec2_fleet" "main" {
  type                             = "maintain"
  terminate_instances              = true
  terminate_instances_with_expiration = true
  replace_unhealthy_instances      = true

  depends_on = [
    aws_iam_service_linked_role.ec2_fleet,
    aws_iam_service_linked_role.spot
  ]

  launch_template_config {
    launch_template_specification {
      launch_template_id = aws_launch_template.ec2_fleet.id
      version            = "$Latest"
    }

    override {
      instance_type = var.instance_type
      subnet_id     = aws_subnet.public.id
      priority      = 1
    }

    override {
      instance_type = var.instance_type
      subnet_id     = aws_subnet.private.id
      priority      = 2
    }
  }

  target_capacity_specification {
    total_target_capacity       = 9
    on_demand_target_capacity   = 5
    spot_target_capacity        = 4
    default_target_capacity_type = "on-demand"
  }

  on_demand_options {
    allocation_strategy = "prioritized"
  }

  spot_options {
    allocation_strategy                 = "capacity-optimized"
    instance_interruption_behavior      = "terminate"
    instance_pools_to_use_count         = 1
  }

  tag_specification {
    resource_type = "fleet"

    tags = {
      Name = "amazon-linux-2-mixed-ec2-fleet"
    }
  }
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet."
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet."
  value       = aws_subnet.private.id
}

output "latest_amazon_linux_2_ami_id" {
  description = "AMI ID of the latest Amazon Linux 2 image."
  value       = data.aws_ami.amazon_linux_2.id
}

output "launch_template_id" {
  description = "ID of the EC2 Launch Template."
  value       = aws_launch_template.ec2_fleet.id
}

output "ec2_fleet_id" {
  description = "ID of the EC2 Fleet."
  value       = aws_ec2_fleet.main.id
}