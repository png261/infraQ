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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet."
  type        = string
  default     = "10.0.1.0/24"
}

resource "aws_vpc" "efs_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "efs-vpc"
  }
}

resource "aws_internet_gateway" "efs_igw" {
  vpc_id = aws_vpc.efs_vpc.id

  tags = {
    Name = "efs-internet-gateway"
  }
}

resource "aws_subnet" "efs_subnet" {
  vpc_id                  = aws_vpc.efs_vpc.id
  cidr_block              = var.subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "efs-subnet"
  }
}

resource "aws_route_table" "efs_route_table" {
  vpc_id = aws_vpc.efs_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.efs_igw.id
  }

  tags = {
    Name = "efs-route-table"
  }
}

resource "aws_route_table_association" "efs_route_table_association" {
  subnet_id      = aws_subnet.efs_subnet.id
  route_table_id = aws_route_table.efs_route_table.id
}

resource "aws_security_group" "efs_security_group" {
  name        = "efs-security-group"
  description = "Allow NFS traffic for EFS"
  vpc_id      = aws_vpc.efs_vpc.id

  ingress {
    description = "Allow NFS from within the VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "efs-security-group"
  }
}

resource "aws_efs_file_system" "efs" {
  creation_token   = "example-efs-file-system"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name = "example-efs"
  }
}

resource "aws_efs_mount_target" "efs_mount_target" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = aws_subnet.efs_subnet.id
  security_groups = [aws_security_group.efs_security_group.id]
}

output "efs_file_system_id" {
  description = "The ID of the EFS file system."
  value       = aws_efs_file_system.efs.id
}

output "efs_dns_name" {
  description = "The DNS name of the EFS file system."
  value       = aws_efs_file_system.efs.dns_name
}

output "efs_mount_target_id" {
  description = "The ID of the EFS mount target."
  value       = aws_efs_mount_target.efs_mount_target.id
}