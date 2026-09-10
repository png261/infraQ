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
  description = "AWS region to deploy the RDS PostgreSQL instance."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "airbyte-rds-test"
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "airbyte_test"
}

variable "db_username" {
  description = "Master username for PostgreSQL."
  type        = string
  default     = "airbyte_admin"
}

variable "db_password" {
  description = "Master password for PostgreSQL. Change this in real deployments."
  type        = string
  sensitive   = true
  default     = "AirbyteTestPassword123!"
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to PostgreSQL. Restrict this for real deployments."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GB."
  type        = number
  default     = 20
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.80.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

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
  cidr_block              = "10.80.1.0/24"
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
  cidr_block              = "10.80.2.0/24"
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

resource "aws_route" "public_internet" {
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
    Environment = "test"
  }
}

resource "aws_security_group" "postgres" {
  name        = "${var.project_name}-postgres-sg"
  description = "Allow PostgreSQL access for Airbyte connector tests"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "PostgreSQL access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
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

resource "aws_db_parameter_group" "postgres15" {
  name        = "${var.project_name}-postgres15-params"
  family      = "postgres15"
  description = "Managed PostgreSQL 15 parameter group for Airbyte connector tests"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = {
    Name        = "${var.project_name}-postgres15-params"
    Environment = "test"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-postgres15"

  engine         = "postgres"
  engine_version = "15"
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  allocated_storage     = var.allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  publicly_accessible    = true

  port = 5432

  parameter_group_name = aws_db_parameter_group.postgres15.name

  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  auto_minor_version_upgrade = true
  apply_immediately          = true

  monitoring_interval = 0

  deletion_protection = false
  skip_final_snapshot = true

  copy_tags_to_snapshot = true

  tags = {
    Name        = "${var.project_name}-postgres15"
    Environment = "test"
    Purpose     = "airbyte-connector-tests"
  }
}

output "rds_endpoint" {
  description = "PostgreSQL RDS endpoint."
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "PostgreSQL RDS port."
  value       = aws_db_instance.postgres.port
}

output "database_name" {
  description = "Initial database name."
  value       = aws_db_instance.postgres.db_name
}

output "database_username" {
  description = "Database master username."
  value       = aws_db_instance.postgres.username
  sensitive   = true
}

output "jdbc_connection_string" {
  description = "JDBC connection string for Airbyte connector tests."
  value       = "jdbc:postgresql://${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${aws_db_instance.postgres.db_name}"
}