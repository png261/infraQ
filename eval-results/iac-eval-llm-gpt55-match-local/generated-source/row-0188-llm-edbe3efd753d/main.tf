terraform {
  required_version = ">= 1.3.0"

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

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "amazon-linux-2-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "amazon-linux-2-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "amazon-linux-2-public-rt"
  }
}

resource "aws_subnet" "subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "amazon-linux-2-subnet-us-east-1a"
  }
}

resource "aws_subnet" "subnet_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "amazon-linux-2-subnet-us-east-1b"
  }
}

resource "aws_route_table_association" "subnet_a" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "subnet_b" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "instance_sg" {
  name        = "amazon-linux-2-instance-sg"
  description = "Security group for Amazon Linux 2 instances"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "amazon-linux-2-instance-sg"
  }
}

resource "aws_instance" "instance_a" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.subnet_a.id
  vpc_security_group_ids      = [aws_security_group.instance_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "amazon-linux-2-instance-us-east-1a"
  }
}

resource "aws_instance" "instance_b" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.subnet_b.id
  vpc_security_group_ids      = [aws_security_group.instance_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "amazon-linux-2-instance-us-east-1b"
  }
}

resource "aws_ebs_volume" "volume_a" {
  availability_zone = "us-east-1a"
  size              = 50
  type              = "gp3"

  tags = {
    Name = "amazon-linux-2-ebs-volume-us-east-1a"
  }
}

resource "aws_ebs_volume" "volume_b" {
  availability_zone = "us-east-1b"
  size              = 50
  type              = "gp3"

  tags = {
    Name = "amazon-linux-2-ebs-volume-us-east-1b"
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

output "instance_a_id" {
  value = aws_instance.instance_a.id
}

output "instance_b_id" {
  value = aws_instance.instance_b.id
}

output "instance_a_public_ip" {
  value = aws_instance.instance_a.public_ip
}

output "instance_b_public_ip" {
  value = aws_instance.instance_b.public_ip
}

output "ebs_volume_a_id" {
  value = aws_ebs_volume.volume_a.id
}

output "ebs_volume_b_id" {
  value = aws_ebs_volume.volume_b.id
}