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
  description = "AWS region where the PostgreSQL RDS instance will be created."
  type        = string
  default     = "us-east-1"
}

variable "db_identifier" {
  description = "The identifier for the RDS PostgreSQL instance."
  type        = string
  default     = "postgres-t4g-large-db"
}

variable "db_name" {
  description = "The initial PostgreSQL database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "The master username for the PostgreSQL database."
  type        = string
  default     = "dbadmin"
}

variable "allocated_storage" {
  description = "Allocated storage size in GB."
  type        = number
  default     = 100
}

variable "max_allocated_storage" {
  description = "Maximum storage size in GB for autoscaling."
  type        = number
  default     = 500
}

variable "allowed_postgres_cidr" {
  description = "CIDR block allowed to connect to PostgreSQL. Restrict this in production."
  type        = string
  default     = "0.0.0.0/0"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "random_password" "db_master_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_security_group" "postgres" {
  name        = "${var.db_identifier}-sg"
  description = "Security group for PostgreSQL RDS"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow PostgreSQL access"
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
    Name = "${var.db_identifier}-sg"
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.db_identifier}-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "${var.db_identifier}-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = var.db_identifier

  engine         = "postgres"
  instance_class = "db.t4g.large"

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_master_password.result

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]

  port                = 5432
  publicly_accessible = true

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  auto_minor_version_upgrade = true
  deletion_protection        = false
  skip_final_snapshot        = true

  performance_insights_enabled = true

  tags = {
    Name        = var.db_identifier
    Environment = "dev"
    Engine      = "postgres"
  }
}

output "postgres_endpoint" {
  description = "The PostgreSQL RDS endpoint."
  value       = aws_db_instance.postgres.endpoint
}

output "postgres_port" {
  description = "The PostgreSQL port."
  value       = aws_db_instance.postgres.port
}

output "postgres_database_name" {
  description = "The initial PostgreSQL database name."
  value       = aws_db_instance.postgres.db_name
}

output "postgres_username" {
  description = "The PostgreSQL master username."
  value       = aws_db_instance.postgres.username
}

output "postgres_password" {
  description = "The generated PostgreSQL master password."
  value       = random_password.db_master_password.result
  sensitive   = true
}