terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the RDS PostgreSQL instance will be created."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "airbyte-postgres-test"
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "airbyte"
}

variable "db_username" {
  description = "Master username for the PostgreSQL database."
  type        = string
  default     = "airbyte_admin"
}

variable "allowed_postgres_cidr" {
  description = "CIDR block allowed to connect to PostgreSQL. For testing, this defaults to all IPv4 addresses."
  type        = string
  default     = "0.0.0.0/0"
}

variable "db_instance_class" {
  description = "RDS instance class for PostgreSQL."
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
  cidr_block           = "10.80.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Application = "airbyte-connector-tests"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Application = "airbyte-connector-tests"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.80.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Application = "airbyte-connector-tests"
    Type        = "public"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.80.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet-b"
    Application = "airbyte-connector-tests"
    Type        = "public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-public-rt"
    Application = "airbyte-connector-tests"
  }
}

resource "aws_route" "public_internet_access" {
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

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Application = "airbyte-connector-tests"
  }
}

resource "aws_security_group" "postgres" {
  name        = "${var.project_name}-postgres-sg"
  description = "Allow PostgreSQL access for Airbyte connector test cases"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "PostgreSQL access"
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
    Name        = "${var.project_name}-postgres-sg"
    Application = "airbyte-connector-tests"
  }
}

resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "${var.project_name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-rds-monitoring-role"
    Application = "airbyte-connector-tests"
  }
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_parameter_group" "postgres15" {
  name        = "${var.project_name}-postgres15-params"
  family      = "postgres15"
  description = "Managed PostgreSQL 15 parameter group for Airbyte connector tests"

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "rds.force_ssl"
    value = "0"
  }

  tags = {
    Name        = "${var.project_name}-postgres15-params"
    Application = "airbyte-connector-tests"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-rds"

  engine         = "postgres"
  engine_version = "15"
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_master_password.result

  allocated_storage     = 500
  max_allocated_storage = 1000
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  publicly_accessible    = true

  port = 5432

  parameter_group_name = aws_db_parameter_group.postgres15.name

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  auto_minor_version_upgrade = true
  apply_immediately          = true

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  deletion_protection = false
  skip_final_snapshot = true

  copy_tags_to_snapshot = true

  enabled_cloudwatch_logs_exports = [
    "postgresql",
    "upgrade"
  ]

  tags = {
    Name        = "${var.project_name}-postgres15-rds"
    Application = "airbyte-connector-tests"
    Engine      = "postgresql15"
    StorageGB   = "500"
  }

  depends_on = [
    aws_iam_role_policy_attachment.rds_enhanced_monitoring,
    aws_route_table_association.public_a,
    aws_route_table_association.public_b
  ]
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint."
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "RDS PostgreSQL port."
  value       = aws_db_instance.postgres.port
}

output "rds_database_name" {
  description = "Initial PostgreSQL database name."
  value       = aws_db_instance.postgres.db_name
}

output "rds_username" {
  description = "PostgreSQL master username."
  value       = aws_db_instance.postgres.username
}

output "rds_password" {
  description = "PostgreSQL master password."
  value       = random_password.db_master_password.result
  sensitive   = true
}

output "postgres_connection_string" {
  description = "PostgreSQL connection string for Airbyte connector tests."
  value       = "postgresql://${aws_db_instance.postgres.username}:${random_password.db_master_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${aws_db_instance.postgres.db_name}"
  sensitive   = true
}