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
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "basicdb"
}

variable "db_username" {
  description = "Master username for the RDS instance."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the RDS instance."
  type        = string
  sensitive   = true
  default     = "ChangeMe123456!"
}

variable "vpc_cidr" {
  description = "CIDR block for the RDS VPC."
  type        = string
  default     = "10.0.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "rds_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "basic-rds-vpc"
  }
}

resource "aws_subnet" "rds_private_subnet_1" {
  vpc_id                  = aws_vpc.rds_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "basic-rds-private-subnet-1"
  }
}

resource "aws_subnet" "rds_private_subnet_2" {
  vpc_id                  = aws_vpc.rds_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "basic-rds-private-subnet-2"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "basic-rds-security-group"
  description = "Allow MySQL access within the VPC"
  vpc_id      = aws_vpc.rds_vpc.id

  ingress {
    description = "Allow MySQL from within VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.rds_vpc.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "basic-rds-security-group"
  }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name        = "basic-rds-subnet-group"
  description = "Subnet group for basic RDS instance"

  subnet_ids = [
    aws_subnet.rds_private_subnet_1.id,
    aws_subnet.rds_private_subnet_2.id
  ]

  tags = {
    Name = "basic-rds-subnet-group"
  }
}

resource "aws_db_instance" "basic_rds" {
  identifier = "basic-rds-io1"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  allocated_storage = 100
  storage_type      = "io1"
  iops              = 1000
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  apply_immediately = true

  tags = {
    Name = "basic-rds-io1"
  }
}

output "rds_endpoint" {
  description = "The connection endpoint for the RDS instance."
  value       = aws_db_instance.basic_rds.endpoint
}

output "rds_port" {
  description = "The port the RDS instance listens on."
  value       = aws_db_instance.basic_rds.port
}

output "rds_database_name" {
  description = "The initial database name."
  value       = aws_db_instance.basic_rds.db_name
}