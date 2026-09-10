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

locals {
  cluster_availability_zone = "us-east-1c"
  cluster_instance_type     = "m5.large"
}

data "aws_ami" "amazon_linux_2023" {
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

resource "aws_vpc" "cluster" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "cluster-placement-vpc"
  }
}

resource "aws_subnet" "cluster_a" {
  vpc_id            = aws_vpc.cluster.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = local.cluster_availability_zone

  tags = {
    Name = "cluster-placement-subnet-a"
  }
}

resource "aws_subnet" "cluster_b" {
  vpc_id            = aws_vpc.cluster.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "cluster-placement-subnet-b"
  }
}

resource "aws_security_group" "cluster" {
  name        = "cluster-placement-sg"
  description = "Security group for clustered placement group instances"
  vpc_id      = aws_vpc.cluster.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cluster-placement-sg"
  }
}

resource "aws_placement_group" "cluster" {
  name     = "cluster-placement-group"
  strategy = "cluster"
}

resource "aws_instance" "cluster" {
  count = 3

  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = local.cluster_instance_type
  subnet_id              = aws_subnet.cluster_a.id
  vpc_security_group_ids = [aws_security_group.cluster.id]
  placement_group        = aws_placement_group.cluster.name

  tags = {
    Name = "cluster-placement-instance-${count.index + 1}"
  }
}
