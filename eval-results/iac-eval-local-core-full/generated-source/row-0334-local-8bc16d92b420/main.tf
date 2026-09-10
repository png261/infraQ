terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "airbyte_tests" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "airbyte-rds-test-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.airbyte_tests.id
  cidr_block              = "10.42.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "airbyte-rds-test-public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.airbyte_tests.id
  cidr_block              = "10.42.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "airbyte-rds-test-private-subnet"
  }
}

resource "aws_db_subnet_group" "airbyte_tests" {
  name       = "airbyte-rds-test-subnet-group"
  subnet_ids = [aws_subnet.public.id, aws_subnet.private.id]

  tags = {
    Name = "airbyte-rds-test-subnet-group"
  }
}

resource "aws_security_group" "rds" {
  name        = "airbyte-rds-test-sg"
  description = "Restrict PostgreSQL access to VPC CIDR for Airbyte connector tests"
  vpc_id      = aws_vpc.airbyte_tests.id

  ingress {
    description = "PostgreSQL from within the test VPC only"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.airbyte_tests.cidr_block]
  }

  egress {
    description = "Allow outbound responses"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "airbyte-rds-test-sg"
  }
}

resource "aws_db_parameter_group" "postgres" {
  name        = "airbyte-rds-test-postgres12"
  family      = "postgres12"
  description = "Managed low-maintenance PostgreSQL parameters for Airbyte connector tests"

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = {
    Name = "airbyte-rds-test-postgres12"
  }
}

resource "aws_db_instance" "airbyte_tests" {
  identifier             = "airbyte-rds-test-postgres"
  allocated_storage      = 20
  max_allocated_storage  = 100
  storage_type           = "gp3"
  engine                 = "postgres"
  engine_version         = "12.6"
  instance_class         = "db.t3.micro"
  db_name                = "airbytetest"
  username               = "airbyte"
  password               = "AirbyteTestPassword123!"
  parameter_group_name   = aws_db_parameter_group.postgres.name
  db_subnet_group_name   = aws_db_subnet_group.airbyte_tests.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false
  apply_immediately      = true
  backup_retention_period = 7
  auto_minor_version_upgrade = true
  monitoring_interval    = 0

  tags = {
    Name = "airbyte-rds-test-postgres"
  }
}
