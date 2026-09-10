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
  description = "EC2 instance type for the fleet."
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
    Name = "ec2-fleet-public-route-table"
  }
}

resource "aws_route" "public_internet_access" {
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
    Name = "ec2-fleet-private-route-table"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "fleet_instances" {
  name        = "ec2-fleet-instance-sg"
  description = "Security group for EC2 Fleet instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow ICMP from within the VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound IPv4 traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-fleet-instance-sg"
  }
}

resource "aws_launch_template" "amazon_linux_2" {
  name_prefix   = "amazon-linux-2-fleet-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type

  vpc_security_group_ids = [
    aws_security_group.fleet_instances.id
  ]

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "ec2-fleet-amazon-linux-2-instance"
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
  EOF
  )

  tags = {
    Name = "amazon-linux-2-fleet-launch-template"
  }
}

resource "aws_ec2_fleet" "main" {
  type = "maintain"

  target_capacity_specification {
    total_target_capacity       = 9
    on_demand_target_capacity   = 5
    spot_target_capacity        = 4
    default_target_capacity_type = "on-demand"
  }

  on_demand_options {
    allocation_strategy = "lowestPrice"
  }

  spot_options {
    allocation_strategy           = "priceCapacityOptimized"
    instance_interruption_behavior = "terminate"
  }

  launch_template_config {
    launch_template_specification {
      launch_template_id = aws_launch_template.amazon_linux_2.id
      version            = "$Latest"
    }

    override {
      instance_type = var.instance_type
      subnet_id     = aws_subnet.public.id
    }

    override {
      instance_type = var.instance_type
      subnet_id     = aws_subnet.private.id
    }
  }

  replace_unhealthy_instances = true

  tags = {
    Name = "amazon-linux-2-mixed-ec2-fleet"
  }

  depends_on = [
    aws_route_table_association.public,
    aws_route_table_association.private
  ]
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

output "launch_template_id" {
  description = "ID of the EC2 launch template."
  value       = aws_launch_template.amazon_linux_2.id
}

output "amazon_linux_2_ami_id" {
  description = "Newest Amazon Linux 2 AMI ID selected for the fleet."
  value       = data.aws_ami.amazon_linux_2.id
}

output "ec2_fleet_id" {
  description = "ID of the EC2 Fleet."
  value       = aws_ec2_fleet.main.id
}