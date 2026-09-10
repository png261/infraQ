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
  description = "AWS region where the EFS file system will be created."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "efs-system-policy-demo"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnet_a_cidr" {
  description = "CIDR block for the first subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "subnet_b_cidr" {
  description = "CIDR block for the second subnet."
  type        = string
  default     = "10.20.2.0/24"
}

data "aws_caller_identity" "current" {}

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

resource "aws_subnet" "a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_a_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet-a"
  }
}

resource "aws_subnet" "b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_b_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route" "default_ipv4" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "efs" {
  name        = "${var.project_name}-efs-sg"
  description = "Security group for EFS mount targets"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow NFS traffic from within the VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
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

  tags = {
    Name = "${var.project_name}-efs"
  }
}

resource "aws_efs_mount_target" "a" {
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.a.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "b" {
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.b.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_file_system_policy" "main" {
  file_system_id = aws_efs_file_system.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${var.project_name}-efs-system-policy"

    Statement = [
      {
        Sid    = "DenyNonTLSAccess"
        Effect = "Deny"

        Principal = {
          AWS = "*"
        }

        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]

        Resource = aws_efs_file_system.main.arn

        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AllowAccountRootAccess"
        Effect = "Allow"

        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }

        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]

        Resource = aws_efs_file_system.main.arn

        Condition = {
          Bool = {
            "elasticfilesystem:AccessedViaMountTarget" = "true"
          }
        }
      }
    ]
  })
}

output "efs_file_system_id" {
  description = "ID of the EFS file system."
  value       = aws_efs_file_system.main.id
}

output "efs_file_system_arn" {
  description = "ARN of the EFS file system."
  value       = aws_efs_file_system.main.arn
}

output "efs_dns_name" {
  description = "DNS name of the EFS file system."
  value       = aws_efs_file_system.main.dns_name
}

output "efs_mount_target_a_id" {
  description = "ID of the first EFS mount target."
  value       = aws_efs_mount_target.a.id
}

output "efs_mount_target_b_id" {
  description = "ID of the second EFS mount target."
  value       = aws_efs_mount_target.b.id
}