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
  description = "AWS region to deploy the Neptune cluster into."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Name prefix for all resources."
  type        = string
  default     = "basic-neptune"
}

variable "neptune_engine_version" {
  description = "Neptune engine version."
  type        = string
  default     = "1.2.1.0"
}

variable "neptune_parameter_group_family" {
  description = "Neptune parameter group family compatible with the selected engine version."
  type        = string
  default     = "neptune1.2"
}

variable "neptune_instance_class" {
  description = "Instance class for the Neptune DB instance."
  type        = string
  default     = "db.t3.medium"
}

variable "neptune_port" {
  description = "Port used by Neptune."
  type        = number
  default     = 8182
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-subnet-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.40.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-subnet-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route" "default_ipv4" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "neptune" {
  name        = "${var.name_prefix}-sg"
  description = "Security group for Neptune cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow Neptune access from within the VPC"
    from_port   = var.neptune_port
    to_port     = var.neptune_port
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
    Name = "${var.name_prefix}-sg"
  }
}

resource "aws_neptune_subnet_group" "main" {
  name        = "${var.name_prefix}-subnet-group"
  description = "Subnet group for ${var.name_prefix} Neptune cluster"

  subnet_ids = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  tags = {
    Name = "${var.name_prefix}-subnet-group"
  }
}

resource "aws_neptune_cluster_parameter_group" "custom" {
  name        = "${var.name_prefix}-cluster-pg"
  family      = var.neptune_parameter_group_family
  description = "Custom Neptune cluster parameter group"

  parameter {
    name         = "neptune_enable_audit_log"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "${var.name_prefix}-cluster-pg"
  }
}

resource "aws_neptune_parameter_group" "custom" {
  name        = "${var.name_prefix}-instance-pg"
  family      = var.neptune_parameter_group_family
  description = "Custom Neptune instance parameter group"

  parameter {
    name         = "neptune_query_timeout"
    value        = "120000"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "${var.name_prefix}-instance-pg"
  }
}

resource "aws_neptune_cluster" "main" {
  cluster_identifier                  = "${var.name_prefix}-cluster"
  engine                              = "neptune"
  engine_version                      = var.neptune_engine_version
  neptune_cluster_parameter_group_name = aws_neptune_cluster_parameter_group.custom.name
  neptune_subnet_group_name            = aws_neptune_subnet_group.main.name
  vpc_security_group_ids               = [aws_security_group.neptune.id]

  port                          = var.neptune_port
  storage_encrypted             = true
  backup_retention_period       = 1
  preferred_backup_window       = "07:00-09:00"
  preferred_maintenance_window  = "sun:09:00-sun:10:00"
  skip_final_snapshot           = true
  deletion_protection           = false
  apply_immediately             = true

  tags = {
    Name = "${var.name_prefix}-cluster"
  }
}

resource "aws_neptune_cluster_instance" "main" {
  identifier                  = "${var.name_prefix}-instance-1"
  cluster_identifier          = aws_neptune_cluster.main.id
  engine                      = "neptune"
  engine_version              = var.neptune_engine_version
  instance_class              = var.neptune_instance_class
  neptune_parameter_group_name = aws_neptune_parameter_group.custom.name
  neptune_subnet_group_name    = aws_neptune_subnet_group.main.name

  publicly_accessible       = false
  auto_minor_version_upgrade = true
  apply_immediately         = true

  tags = {
    Name = "${var.name_prefix}-instance-1"
  }
}

output "neptune_cluster_endpoint" {
  description = "Writer endpoint for the Neptune cluster."
  value       = aws_neptune_cluster.main.endpoint
}

output "neptune_cluster_reader_endpoint" {
  description = "Reader endpoint for the Neptune cluster."
  value       = aws_neptune_cluster.main.reader_endpoint
}

output "neptune_port" {
  description = "Neptune port."
  value       = aws_neptune_cluster.main.port
}

output "neptune_instance_id" {
  description = "ID of the Neptune cluster instance."
  value       = aws_neptune_cluster_instance.main.id
}