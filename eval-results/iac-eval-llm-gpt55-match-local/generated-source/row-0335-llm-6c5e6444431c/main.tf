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
  default     = "airbytetest"
}

variable "db_username" {
  description = "Master username for the PostgreSQL database."
  type        = string
  default     = "airbyte_admin"
}

variable "allowed_postgres_cidr" {
  description = "CIDR block allowed to connect to PostgreSQL. For testing this defaults to open access; restrict in production."
  type        = string
  default     = "0.0.0.0/0"
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = "test"
    ManagedBy   = "terraform"
    Purpose     = "airbyte-connector-tests"
  }
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
  cidr_block           = "10.40.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-a"
    Tier = "public"
  })
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.40.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-b"
    Tier = "public"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
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

resource "aws_security_group" "rds_postgres" {
  name        = "${var.project_name}-rds-postgres-sg"
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

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-rds-postgres-sg"
  })
}

resource "aws_db_subnet_group" "public" {
  name        = "${var.project_name}-public-db-subnet-group"
  description = "Public subnet group for Airbyte PostgreSQL test RDS instance"

  subnet_ids = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-db-subnet-group"
  })
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-postgres-15"

  engine         = "postgres"
  engine_version = "15"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.public.name
  vpc_security_group_ids = [aws_security_group.rds_postgres.id]
  publicly_accessible    = true

  multi_az               = false
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  auto_minor_version_upgrade = true
  apply_immediately          = true

  deletion_protection = false
  skip_final_snapshot = true

  performance_insights_enabled = false
  monitoring_interval          = 0

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-postgres-15"
  })
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint address."
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "RDS PostgreSQL port."
  value       = aws_db_instance.postgres.port
}

output "database_name" {
  description = "Initial PostgreSQL database name."
  value       = aws_db_instance.postgres.db_name
}

output "database_username" {
  description = "PostgreSQL master username."
  value       = var.db_username
}

output "database_password" {
  description = "PostgreSQL master password."
  value       = random_password.db_password.result
  sensitive   = true
}

output "jdbc_url" {
  description = "JDBC connection URL for Airbyte connector tests."
  value       = "jdbc:postgresql://${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${aws_db_instance.postgres.db_name}"
}

output "public_subnet_ids" {
  description = "Public subnet IDs used by the RDS subnet group."
  value = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]
}