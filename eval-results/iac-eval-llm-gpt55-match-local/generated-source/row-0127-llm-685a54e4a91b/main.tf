terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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

resource "aws_vpc" "custom_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "custom-vpc"
  }
}

resource "aws_subnet" "subnet_a" {
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "custom-subnet-us-east-1a"
  }
}

resource "aws_subnet" "subnet_b" {
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "custom-subnet-us-east-1b"
  }
}

resource "aws_security_group" "ec2_security_group" {
  name        = "custom-vpc-ec2-sg"
  description = "Security group for EC2 instances in custom VPC"
  vpc_id      = aws_vpc.custom_vpc.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "custom-vpc-ec2-sg"
  }
}

resource "aws_instance" "instance_a" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.subnet_a.id
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]

  tags = {
    Name = "amazon-linux-2-us-east-1a"
  }
}

resource "aws_instance" "instance_b" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.subnet_b.id
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]

  tags = {
    Name = "amazon-linux-2-us-east-1b"
  }
}

resource "aws_ebs_volume" "volume_a" {
  availability_zone = "us-east-1a"
  size              = 50
  type              = "gp3"

  tags = {
    Name = "ebs-volume-us-east-1a"
  }
}

resource "aws_ebs_volume" "volume_b" {
  availability_zone = "us-east-1b"
  size              = 50
  type              = "gp3"

  tags = {
    Name = "ebs-volume-us-east-1b"
  }
}

resource "aws_volume_attachment" "attachment_a" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.volume_a.id
  instance_id = aws_instance.instance_a.id
}

resource "aws_volume_attachment" "attachment_b" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.volume_b.id
  instance_id = aws_instance.instance_b.id
}

output "vpc_id" {
  value = aws_vpc.custom_vpc.id
}

output "subnet_a_id" {
  value = aws_subnet.subnet_a.id
}

output "subnet_b_id" {
  value = aws_subnet.subnet_b.id
}

output "instance_a_id" {
  value = aws_instance.instance_a.id
}

output "instance_b_id" {
  value = aws_instance.instance_b.id
}

output "ebs_volume_a_id" {
  value = aws_ebs_volume.volume_a.id
}

output "ebs_volume_b_id" {
  value = aws_ebs_volume.volume_b.id
}