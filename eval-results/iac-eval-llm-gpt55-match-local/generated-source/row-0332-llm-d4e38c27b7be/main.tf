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

variable "vpc_id" {
  description = "ID of the VPC where the RDS instance should be deployed. If null, the default VPC is used."
  type        = string
  default     = null
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to PostgreSQL on port 5432."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "db_identifier" {
  description = "Identifier for the RDS PostgreSQL instance."
  type        = string
  default     = "secure-postgresql-db"
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the PostgreSQL database."
  type        = string
  default     = "dbadmin"
}

variable "postgres_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "15.8"
}

variable "allocated_storage" {
  description = "Allocated storage size in GB."
  type        = number
  default     = 20
}

data "aws_vpc" "selected" {
  id      = var.vpc_id
  default = var.vpc_id == null ? true : null
}

data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

resource "random_password" "db_master_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_kms_key" "rds" {
  description             = "Customer managed KMS key for encrypting PostgreSQL RDS storage"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "secure-postgresql-rds-kms-key"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/secure-postgresql-rds"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_security_group" "rds" {
  name        = "secure-postgresql-rds-sg"
  description = "Security group for PostgreSQL RDS instance"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    description = "Allow PostgreSQL access from approved CIDR blocks"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "Allow outbound traffic from RDS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "secure-postgresql-rds-sg"
  }
}

resource "aws_db_subnet_group" "postgresql" {
  name        = "secure-postgresql-db-subnet-group"
  description = "Subnet group for secure PostgreSQL RDS instance"
  subnet_ids  = data.aws_subnets.selected.ids

  tags = {
    Name = "secure-postgresql-db-subnet-group"
  }
}

resource "aws_db_parameter_group" "postgresql" {
  name        = "secure-postgresql-parameter-group"
  description = "Custom PostgreSQL parameter group"
  family      = "postgres15"

  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "immediate"
  }

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "secure-postgresql-parameter-group"
  }
}

resource "aws_db_instance" "postgresql" {
  identifier = var.db_identifier

  engine         = "postgres"
  engine_version = var.postgres_engine_version
  instance_class = "db.t3.micro"

  allocated_storage     = var.allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds.arn

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_master_password.result

  port = 5432

  multi_az                = true
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.postgresql.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  parameter_group_name = aws_db_parameter_group.postgresql.name

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  auto_minor_version_upgrade = true
  deletion_protection        = true
  skip_final_snapshot        = false
  final_snapshot_identifier  = "${var.db_identifier}-final-snapshot"

  monitoring_interval = 0

  enabled_cloudwatch_logs_exports = [
    "postgresql",
    "upgrade"
  ]

  copy_tags_to_snapshot = true

  tags = {
    Name        = var.db_identifier
    Environment = "production"
  }

  depends_on = [
    aws_kms_key.rds,
    aws_db_subnet_group.postgresql,
    aws_db_parameter_group.postgresql
  ]
}

output "rds_endpoint" {
  description = "Endpoint address of the PostgreSQL RDS instance."
  value       = aws_db_instance.postgresql.address
}

output "rds_port" {
  description = "Port of the PostgreSQL RDS instance."
  value       = aws_db_instance.postgresql.port
}

output "rds_database_name" {
  description = "Initial database name."
  value       = aws_db_instance.postgresql.db_name
}

output "rds_username" {
  description = "Master username for the PostgreSQL database."
  value       = aws_db_instance.postgresql.username
  sensitive   = true
}

output "rds_master_password" {
  description = "Generated master password for the PostgreSQL database."
  value       = random_password.db_master_password.result
  sensitive   = true
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for RDS encryption."
  value       = aws_kms_key.rds.arn
}