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

############################
# Variables
############################

variable "aws_region" {
  description = "AWS region to deploy resources into."
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

variable "allowed_postgres_cidr_blocks" {
  description = "CIDR blocks allowed to connect to PostgreSQL. Restrict this in production."
  type        = list(string)
  default     = ["10.20.0.0/16"]
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for PostgreSQL."
  type        = string
  default     = "dbadmin"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.medium"
}

variable "db_allocated_storage" {
  description = "Initial allocated storage in GB."
  type        = number
  default     = 50
}

variable "db_max_allocated_storage" {
  description = "Maximum autoscaled storage in GB."
  type        = number
  default     = 200
}

variable "postgres_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.3"
}

variable "backup_retention_period" {
  description = "Number of days to retain backups."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Enable deletion protection for the RDS instance."
  type        = bool
  default     = true
}

############################
# Data Sources
############################

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

############################
# Networking
############################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = "production"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.project_name}-private-subnet-${count.index + 1}"
    Environment = "production"
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = "production"
  }
}

############################
# Security Group
############################

resource "aws_security_group" "postgres" {
  name        = "${var.project_name}-postgres-sg"
  description = "Security group for PostgreSQL RDS access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow PostgreSQL access from approved CIDR blocks"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_postgres_cidr_blocks
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-postgres-sg"
    Environment = "production"
  }
}

############################
# KMS Encryption
############################

resource "aws_kms_key" "rds" {
  description             = "KMS key for encrypting PostgreSQL RDS storage"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowRDSUseOfKey"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-rds-kms-key"
    Environment = "production"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

############################
# Random Database Password
############################

resource "random_password" "db_master_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

############################
# PostgreSQL Parameter Group
############################

resource "aws_db_parameter_group" "postgres" {
  name        = "${var.project_name}-postgres16-params"
  family      = "postgres16"
  description = "Custom PostgreSQL parameter group for ${var.project_name}"

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
    Name        = "${var.project_name}-postgres-parameter-group"
    Environment = "production"
  }
}

############################
# RDS PostgreSQL Instance
############################

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-db"

  engine         = "postgres"
  engine_version = var.postgres_engine_version
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_master_password.result

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds.arn

  multi_az               = true
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]

  parameter_group_name = aws_db_parameter_group.postgres.name

  port = 5432

  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true
  deletion_protection        = var.deletion_protection

  enabled_cloudwatch_logs_exports = [
    "postgresql",
    "upgrade"
  ]

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.rds.arn
  performance_insights_retention_period = 7

  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-final-snapshot"

  apply_immediately = false

  tags = {
    Name        = "${var.project_name}-postgres-db"
    Environment = "production"
  }
}

############################
# Outputs
############################

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by the RDS subnet group."
  value       = aws_subnet.private[*].id
}

output "db_instance_identifier" {
  description = "RDS PostgreSQL instance identifier."
  value       = aws_db_instance.postgres.identifier
}

output "db_endpoint" {
  description = "RDS PostgreSQL endpoint."
  value       = aws_db_instance.postgres.endpoint
}

output "db_port" {
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
  sensitive   = true
}

output "db_master_password" {
  description = "Generated PostgreSQL master password. Stored in Terraform state."
  value       = random_password.db_master_password.result
  sensitive   = true
}

output "kms_key_arn" {
  description = "KMS key ARN used for RDS encryption."
  value       = aws_kms_key.rds.arn
}

output "security_group_id" {
  description = "Security group ID attached to the RDS instance."
  value       = aws_security_group.postgres.id
}