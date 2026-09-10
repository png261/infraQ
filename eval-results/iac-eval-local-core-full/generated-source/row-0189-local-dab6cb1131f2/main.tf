terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
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
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "iac-eval-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "iac-eval-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "iac-eval-public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "iac-eval-private-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "iac-eval-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_launch_template" "main" {
  name_prefix   = "iac-eval-al2-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "iac-eval-fleet-instance"
    }
  }
}

resource "aws_ec2_fleet" "main" {
  type = "maintain"

  launch_template_config {
    launch_template_specification {
      launch_template_id = aws_launch_template.main.id
      version            = "$Latest"
    }

    override {
      instance_type = "t3.micro"
      subnet_id     = aws_subnet.public.id
    }

    override {
      instance_type = "t3.micro"
      subnet_id     = aws_subnet.private.id
    }
  }

  target_capacity_specification {
    total_target_capacity       = 9
    on_demand_target_capacity   = 5
    spot_target_capacity        = 4
    default_target_capacity_type = "on-demand"
  }

  terminate_instances = true

  tags = {
    Name = "iac-eval-ec2-fleet"
  }
}

resource "aws_autoscaling_group" "main" {
  name                = "iac-eval-asg"
  min_size            = 0
  max_size            = 0
  desired_capacity    = 0
  vpc_zone_identifier = [aws_subnet.public.id, aws_subnet.private.id]

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "iac-eval-asg-instance"
    propagate_at_launch = true
  }
}
