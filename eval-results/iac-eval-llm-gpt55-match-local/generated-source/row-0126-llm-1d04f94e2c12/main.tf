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

variable "instance_type" {
  description = "EC2 instance type that supports 2 cores and 2 threads per core."
  type        = string
  default     = "m5.xlarge"
}

data "aws_ami" "latest_amazon_linux_2" {
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

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "amazon_linux_2_sg" {
  name        = "amazon-linux-2-cpu-options-sg"
  description = "Security group for Amazon Linux 2 instance"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "amazon-linux-2-cpu-options-sg"
  }
}

resource "aws_instance" "amazon_linux_2" {
  ami                    = data.aws_ami.latest_amazon_linux_2.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.amazon_linux_2_sg.id]

  cpu_options {
    core_count       = 2
    threads_per_core = 2
  }

  tags = {
    Name = "latest-amazon-linux-2-cpu-options"
  }
}

output "ami_id" {
  description = "The latest Amazon Linux 2 AMI ID."
  value       = data.aws_ami.latest_amazon_linux_2.id
}

output "instance_id" {
  description = "The EC2 instance ID."
  value       = aws_instance.amazon_linux_2.id
}

output "cpu_core_count" {
  description = "Configured CPU core count."
  value       = aws_instance.amazon_linux_2.cpu_options[0].core_count
}

output "threads_per_core" {
  description = "Configured threads per core."
  value       = aws_instance.amazon_linux_2.cpu_options[0].threads_per_core
}