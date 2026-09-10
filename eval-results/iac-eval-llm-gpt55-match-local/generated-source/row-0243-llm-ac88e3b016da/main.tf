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
  description = "AWS region where the Neptune cluster will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all created resources."
  type        = string
  default     = "basic-neptune"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_1_cidr" {
  description = "CIDR block for the first example subnet allowed to connect to Neptune."
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_2_cidr" {
  description = "CIDR block for the second example subnet allowed to connect to Neptune."
  type        = string
  default     = "10.0.2.0/24"
}

variable "neptune_engine_version" {
  description = "Neptune engine version."
  type        = string
  default     = "1.3.2.0"
}

variable "neptune_parameter_group_family" {
  description = "Neptune cluster parameter group family."
  type        = string
  default     = "neptune1.3"
}

variable "neptune_instance_class" {
  description = "Instance class for the Neptune cluster instance."
  type        = string
  default     = "db.t3.medium"
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

resource "aws_subnet" "example_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_1_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-example-subnet-1"
  }
}

resource "aws_subnet" "example_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_2_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-example-subnet-2"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "example_1" {
  subnet_id      = aws_subnet.example_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "example_2" {
  subnet_id      = aws_subnet.example_2.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "neptune" {
  name        = "${var.project_name}-neptune-sg"
  description = "Allow Neptune access only from the two example subnet CIDR blocks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow Neptune from example subnet 1"
    from_port   = 8182
    to_port     = 8182
    protocol    = "tcp"
    cidr_blocks = [var.subnet_1_cidr]
  }

  ingress {
    description = "Allow Neptune from example subnet 2"
    from_port   = 8182
    to_port     = 8182
    protocol    = "tcp"
    cidr_blocks = [var.subnet_2_cidr]
  }

  egress {
    description = "Allow all outbound traffic from Neptune"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-neptune-sg"
  }
}

resource "aws_neptune_subnet_group" "main" {
  name        = "${var.project_name}-neptune-subnet-group"
  description = "Neptune subnet group containing only the two example subnets"

  subnet_ids = [
    aws_subnet.example_1.id,
    aws_subnet.example_2.id
  ]

  tags = {
    Name = "${var.project_name}-neptune-subnet-group"
  }
}

resource "aws_neptune_cluster_parameter_group" "custom" {
  name        = "${var.project_name}-custom-cluster-pg"
  family      = var.neptune_parameter_group_family
  description = "Custom Neptune cluster parameter group"

  parameter {
    name  = "neptune_enable_audit_log"
    value = "0"
  }

  tags = {
    Name = "${var.project_name}-custom-cluster-pg"
  }
}

resource "aws_neptune_cluster" "main" {
  cluster_identifier                  = "${var.project_name}-cluster"
  engine                              = "neptune"
  engine_version                      = var.neptune_engine_version
  neptune_cluster_parameter_group_name = aws_neptune_cluster_parameter_group.custom.name
  neptune_subnet_group_name           = aws_neptune_subnet_group.main.name
  vpc_security_group_ids              = [aws_security_group.neptune.id]

  port                            = 8182
  storage_encrypted               = true
  iam_database_authentication_enabled = false
  skip_final_snapshot             = true
  deletion_protection             = false
  apply_immediately               = true

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

resource "aws_neptune_cluster_instance" "main" {
  identifier          = "${var.project_name}-instance-1"
  cluster_identifier  = aws_neptune_cluster.main.id
  engine              = "neptune"
  engine_version      = var.neptune_engine_version
  instance_class      = var.neptune_instance_class
  neptune_subnet_group_name = aws_neptune_subnet_group.main.name
  publicly_accessible = false
  apply_immediately   = true

  tags = {
    Name = "${var.project_name}-instance-1"
  }
}

output "neptune_cluster_endpoint" {
  description = "Neptune cluster writer endpoint."
  value       = aws_neptune_cluster.main.endpoint
}

output "neptune_cluster_reader_endpoint" {
  description = "Neptune cluster reader endpoint."
  value       = aws_neptune_cluster.main.reader_endpoint
}

output "allowed_subnet_ids" {
  description = "The two subnet IDs allowed to connect to Neptune."
  value = [
    aws_subnet.example_1.id,
    aws_subnet.example_2.id
  ]
}

output "allowed_subnet_cidrs" {
  description = "The two subnet CIDR blocks allowed to connect to Neptune on port 8182."
  value = [
    var.subnet_1_cidr,
    var.subnet_2_cidr
  ]
}