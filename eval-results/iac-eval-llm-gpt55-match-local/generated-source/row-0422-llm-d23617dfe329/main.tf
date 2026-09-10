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

variable "project_name" {
  description = "Project name used for tagging resources."
  type        = string
  default     = "efs-lifecycle-demo"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr_1" {
  description = "CIDR block for the first subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_cidr_2" {
  description = "CIDR block for the second subnet."
  type        = string
  default     = "10.0.2.0/24"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "subnet_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr_1
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet-1"
  }
}

resource "aws_subnet" "subnet_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr_2
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet-2"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route" "default_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "subnet_1" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "subnet_2" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "efs" {
  name        = "${var.project_name}-efs-sg"
  description = "Allow NFS traffic to EFS"
  vpc_id      = aws_vpc.main.id

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
    Name = "${var.project_name}-efs-sg"
  }
}

resource "aws_efs_file_system" "main" {
  creation_token = "${var.project_name}-efs"

  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = {
    Name = "${var.project_name}-efs"
  }
}

resource "aws_efs_mount_target" "subnet_1" {
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.subnet_1.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "subnet_2" {
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.subnet_2.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_backup_policy" "main" {
  file_system_id = aws_efs_file_system.main.id

  backup_policy {
    status = "ENABLED"
  }
}

output "efs_file_system_id" {
  description = "The ID of the created EFS file system."
  value       = aws_efs_file_system.main.id
}

output "efs_dns_name" {
  description = "The DNS name of the EFS file system."
  value       = aws_efs_file_system.main.dns_name
}

output "efs_mount_target_1_id" {
  description = "The ID of the first EFS mount target."
  value       = aws_efs_mount_target.subnet_1.id
}

output "efs_mount_target_2_id" {
  description = "The ID of the second EFS mount target."
  value       = aws_efs_mount_target.subnet_2.id
}