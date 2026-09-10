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
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the Neptune cluster will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for resources."
  type        = string
  default     = "basic-neptune"
}

variable "vpc_cidr" {
  description = "CIDR block for the Neptune VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private Neptune subnets."
  type        = list(string)
  default     = ["10.40.1.0/24", "10.40.2.0/24"]
}

variable "neptune_instance_class" {
  description = "Instance class for the Neptune cluster instance."
  type        = string
  default     = "db.t3.medium"
}

variable "neptune_engine_version" {
  description = "Neptune engine version."
  type        = string
  default     = "1.3.2.0"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
  }
}

resource "aws_security_group" "neptune" {
  name        = "${var.project_name}-sg"
  description = "Security group for Neptune cluster"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow Neptune access from within the VPC"
    from_port   = 8182
    to_port     = 8182
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-neptune-sg"
  }
}

resource "aws_neptune_cluster_parameter_group" "custom" {
  name        = "${var.project_name}-cluster-parameter-group"
  family      = "neptune1.3"
  description = "Custom Neptune cluster parameter group"

  parameter {
    name         = "neptune_enable_audit_log"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "${var.project_name}-cluster-parameter-group"
  }
}

resource "aws_neptune_subnet_group" "this" {
  name        = "${var.project_name}-subnet-group"
  description = "Subnet group for Neptune cluster"
  subnet_ids  = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-subnet-group"
  }
}

resource "aws_neptune_cluster" "this" {
  cluster_identifier                  = "${var.project_name}-cluster"
  engine                              = "neptune"
  engine_version                      = var.neptune_engine_version
  neptune_cluster_parameter_group_name = aws_neptune_cluster_parameter_group.custom.name
  neptune_subnet_group_name            = aws_neptune_subnet_group.this.name
  vpc_security_group_ids               = [aws_security_group.neptune.id]

  backup_retention_period      = 1
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  iam_database_authentication_enabled = false
  storage_encrypted                   = true
  skip_final_snapshot                 = true
  apply_immediately                   = true

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

resource "aws_neptune_cluster_instance" "this" {
  identifier                  = "${var.project_name}-instance-1"
  cluster_identifier          = aws_neptune_cluster.this.id
  engine                      = "neptune"
  engine_version              = var.neptune_engine_version
  instance_class              = var.neptune_instance_class
  neptune_subnet_group_name   = aws_neptune_subnet_group.this.name
  publicly_accessible         = false
  auto_minor_version_upgrade  = true
  apply_immediately           = true

  tags = {
    Name = "${var.project_name}-instance-1"
  }
}

output "neptune_cluster_endpoint" {
  description = "Primary Neptune cluster endpoint."
  value       = aws_neptune_cluster.this.endpoint
}

output "neptune_cluster_reader_endpoint" {
  description = "Neptune cluster reader endpoint."
  value       = aws_neptune_cluster.this.reader_endpoint
}

output "neptune_port" {
  description = "Neptune database port."
  value       = aws_neptune_cluster.this.port
}

output "neptune_security_group_id" {
  description = "Security group ID attached to the Neptune cluster."
  value       = aws_security_group.neptune.id
}

output "neptune_subnet_group_name" {
  description = "Neptune subnet group name."
  value       = aws_neptune_subnet_group.this.name
}

output "neptune_cluster_parameter_group_name" {
  description = "Custom Neptune cluster parameter group name."
  value       = aws_neptune_cluster_parameter_group.custom.name
}