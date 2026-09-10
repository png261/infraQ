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

resource "aws_vpc" "benchmark" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "iac-eval-benchmark-vpc"
  }
}

resource "aws_subnet" "benchmark" {
  for_each = {
    us-east-1a = "10.0.1.0/24"
    us-east-1b = "10.0.2.0/24"
  }

  vpc_id            = aws_vpc.benchmark.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = {
    Name = "iac-eval-benchmark-subnet-${each.key}"
  }
}

resource "aws_instance" "benchmark" {
  for_each = aws_subnet.benchmark

  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.micro"
  subnet_id     = each.value.id

  tags = {
    Name = "iac-eval-benchmark-instance-${each.key}"
  }
}

resource "aws_ebs_volume" "benchmark" {
  for_each = aws_subnet.benchmark

  availability_zone = each.key
  size              = 50
  type              = "gp3"

  tags = {
    Name = "iac-eval-benchmark-volume-${each.key}"
  }
}

resource "aws_volume_attachment" "benchmark" {
  for_each = aws_instance.benchmark

  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.benchmark[each.key].id
  instance_id = each.value.id
}
