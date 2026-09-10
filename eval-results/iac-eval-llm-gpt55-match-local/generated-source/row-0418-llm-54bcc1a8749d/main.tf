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
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the RDS database."
  type        = string
  default     = "adminuser"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated database storage in GB."
  type        = number
  default     = 20
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "rds-managed-password-vpc"
  }
}

resource "aws_subnet" "db_subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = {
    Name = "rds-db-subnet-a"
  }
}

resource "aws_subnet" "db_subnet_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false

  tags = {
    Name = "rds-db-subnet-b"
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "rds-managed-password-subnet-group"
  subnet_ids = [
    aws_subnet.db_subnet_a.id,
    aws_subnet.db_subnet_b.id
  ]

  tags = {
    Name = "rds-managed-password-subnet-group"
  }
}

resource "aws_security_group" "rds" {
  name        = "rds-managed-password-sg"
  description = "Security group for RDS database"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow MySQL access from within the VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [
      aws_vpc.main.cidr_block
    ]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags = {
    Name = "rds-managed-password-sg"
  }
}

resource "aws_db_instance" "mysql" {
  identifier = "mysql-managed-master-password"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  deletion_protection = false
  skip_final_snapshot = true

  auto_minor_version_upgrade = true

  tags = {
    Name = "mysql-managed-master-password"
  }
}

output "rds_instance_endpoint" {
  description = "The connection endpoint for the RDS instance."
  value       = aws_db_instance.mysql.endpoint
}

output "rds_instance_arn" {
  description = "ARN of the RDS instance."
  value       = aws_db_instance.mysql.arn
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret managed by RDS for the master user password."
  value       = aws_db_instance.mysql.master_user_secret[0].secret_arn
}