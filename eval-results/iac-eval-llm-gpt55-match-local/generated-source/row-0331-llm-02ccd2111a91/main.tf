terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
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
  description = "Name prefix for all resources."
  type        = string
  default     = "secure-postgres"
}

variable "vpc_cidr" {
  description = "CIDR block for the database VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private database subnets."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "allowed_postgres_cidr" {
  description = "CIDR block allowed to connect to PostgreSQL. Restrict this in production."
  type        = string
  default     = "10.20.0.0/16"
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for PostgreSQL."
  type        = string
  default     = "postgresadmin"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.medium"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_password" "db_master_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

resource "aws_kms_key" "rds" {
  description             = "KMS key for encrypting RDS PostgreSQL storage"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-rds-kms-key"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_security_group" "postgres" {
  name        = "${var.project_name}-postgres-sg"
  description = "Security group for PostgreSQL RDS instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow PostgreSQL access from approved CIDR"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.allowed_postgres_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-postgres-sg"
  }
}

resource "aws_db_parameter_group" "postgres15" {
  name        = "${var.project_name}-postgres15-params"
  family      = "postgres15"
  description = "Custom PostgreSQL 15 parameter group"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = {
    Name = "${var.project_name}-postgres15-parameter-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-db"

  engine         = "postgres"
  engine_version = "15"
  instance_class = var.db_instance_class

  allocated_storage     = 50
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds.arn

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_master_password.result

  port = 5432

  multi_az               = true
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]

  parameter_group_name = aws_db_parameter_group.postgres15.name

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  deletion_protection = true
  skip_final_snapshot = false
  final_snapshot_identifier = "${var.project_name}-final-snapshot"

  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  apply_immediately = false

  tags = {
    Name = "${var.project_name}-postgresql-15"
  }
}

output "db_instance_endpoint" {
  description = "RDS PostgreSQL endpoint."
  value       = aws_db_instance.postgres.endpoint
}

output "db_instance_port" {
  description = "RDS PostgreSQL port."
  value       = aws_db_instance.postgres.port
}

output "db_name" {
  description = "Initial PostgreSQL database name."
  value       = aws_db_instance.postgres.db_name
}

output "db_username" {
  description = "PostgreSQL master username."
  value       = aws_db_instance.postgres.username
}

output "db_master_password" {
  description = "Generated PostgreSQL master password."
  value       = random_password.db_master_password.result
  sensitive   = true
}

output "kms_key_arn" {
  description = "KMS key ARN used for RDS encryption."
  value       = aws_kms_key.rds.arn
}

output "vpc_id" {
  description = "VPC ID where the database is deployed."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by the RDS subnet group."
  value       = aws_subnet.private[*].id
}