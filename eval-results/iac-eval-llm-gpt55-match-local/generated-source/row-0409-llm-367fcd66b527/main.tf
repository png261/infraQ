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
  description = "AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "memoryoptimizeddb"
}

variable "db_username" {
  description = "Master username for the PostgreSQL database."
  type        = string
  default     = "postgresadmin"
}

variable "db_instance_class" {
  description = "Memory-optimized RDS instance class."
  type        = string
  default     = "db.r6g.large"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB for the PostgreSQL database."
  type        = number
  default     = 100
}

variable "db_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.3"
}

variable "allowed_postgres_cidr" {
  description = "CIDR block allowed to connect to PostgreSQL."
  type        = string
  default     = "10.0.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "memory-optimized-postgres-vpc"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "memory-optimized-postgres-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "memory-optimized-postgres-private-b"
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "memory-optimized-postgres-subnet-group"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = {
    Name = "memory-optimized-postgres-subnet-group"
  }
}

resource "aws_security_group" "postgres" {
  name        = "memory-optimized-postgres-sg"
  description = "Security group for memory optimized PostgreSQL RDS instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow PostgreSQL traffic from allowed CIDR"
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
    Name = "memory-optimized-postgres-sg"
  }
}

resource "aws_db_parameter_group" "postgres" {
  name        = "memory-optimized-postgres-params"
  family      = "postgres16"
  description = "Parameter group for memory optimized PostgreSQL"

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = {
    Name = "memory-optimized-postgres-params"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "memory-optimized-postgres"

  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 500
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  parameter_group_name   = aws_db_parameter_group.postgres.name

  port                = 5432
  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  auto_minor_version_upgrade = true
  deletion_protection        = false
  skip_final_snapshot        = true

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  monitoring_interval = 0

  tags = {
    Name        = "memory-optimized-postgres"
    Engine      = "PostgreSQL"
    Workload    = "MemoryOptimized"
    Environment = "dev"
  }
}

output "postgres_endpoint" {
  description = "PostgreSQL RDS endpoint."
  value       = aws_db_instance.postgres.address
}

output "postgres_port" {
  description = "PostgreSQL port."
  value       = aws_db_instance.postgres.port
}

output "postgres_database_name" {
  description = "Initial PostgreSQL database name."
  value       = aws_db_instance.postgres.db_name
}

output "postgres_username" {
  description = "PostgreSQL master username."
  value       = aws_db_instance.postgres.username
}

output "postgres_password" {
  description = "Generated PostgreSQL master password."
  value       = random_password.db_password.result
  sensitive   = true
}