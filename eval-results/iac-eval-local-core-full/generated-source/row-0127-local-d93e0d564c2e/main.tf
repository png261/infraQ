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
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "benchmark-vpc"
  }
}

resource "aws_subnet" "az_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "benchmark-subnet-us-east-1a"
  }
}

resource "aws_subnet" "az_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "benchmark-subnet-us-east-1b"
  }
}

resource "aws_instance" "az_a" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.az_a.id

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  tags = {
    Name = "benchmark-instance-us-east-1a"
  }
}

resource "aws_instance" "az_b" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.az_b.id

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  tags = {
    Name = "benchmark-instance-us-east-1b"
  }
}
