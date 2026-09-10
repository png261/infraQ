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
  description = "AWS region where the RDS PostgreSQL instance will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix used for all created resources."
  type        = string
  default     = "airbyte-postgres-test"
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "airbyte_test"
}

variable "db_username" {
  description = "Master username for the PostgreSQL database."
  type        = string
  default     = "airbyte_admin"
}

variable "allowed_postgres_cidr" {
  description = "CIDR block allowed to connect to PostgreSQL. For testing, this defaults to open access. Restrict this in production."
  type        = string
  default     = "0.0.0.0/0"
}

variable "db_instance_class" {
  description = "RDS instance class for PostgreSQL."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  description = "Initial allocated storage in GB."
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Maximum storage in GB for RDS storage autoscaling."
  type        = number
  default     = 100
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
  cidr_block           = "10.42.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = "test"
    Purpose     = "airbyte-connector-tests"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = "test"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.42.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-a"
    Environment = "test"
    Tier        = "public"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.42.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-b"
    Environment = "test"
    Tier        = "public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = "test"
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

resource "aws_security_group" "postgres" {
  name        = "${var.project_name}-postgres-sg"
  description = "Security group for public PostgreSQL RDS used by Airbyte connector tests"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "PostgreSQL access for Airbyte connector tests"
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
    Environment = "test"
  }
}

resource "aws_db_subnet_group" "postgres" {
  name        = "${var.project_name}-db-subnet-group"
  description = "Public subnet group for Airbyte PostgreSQL test RDS instance"

  subnet_ids = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = "test"
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
    Environment = "test"
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
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }

  tags = {
    Name        = "${var.project_name}-postgres15-params"
    Environment = "test"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-db"

  engine         = "postgres"
  engine_version = "15"
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  port = 5432

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  publicly_accessible    = true

  parameter_group_name = aws_db_parameter_group.postgres15.name

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  auto_minor_version_upgrade = true
  allow_major_version_upgrade = false

  deletion_protection = false
  skip_final_snapshot = true

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  enabled_cloudwatch_logs_exports = [
    "postgresql",
    "upgrade"
  ]

  copy_tags_to_snapshot = true

  tags = {
    Name        = "${var.project_name}-postgres-db"
    Environment = "test"
    Purpose     = "airbyte-connector-tests"
  }

  depends_on = [
    aws_iam_role_policy_attachment.rds_enhanced_monitoring
  ]
}

output "postgres_endpoint" {
  description = "Public endpoint of the PostgreSQL RDS instance."
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

output "postgres_jdbc_url" {
  description = "JDBC URL for the PostgreSQL database."
  value       = "jdbc:postgresql://${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${aws_db_instance.postgres.db_name}"
}

output "postgres_airbyte_host" {
  description = "Hostname to use in Airbyte connector tests."
  value       = aws_db_instance.postgres.address
}