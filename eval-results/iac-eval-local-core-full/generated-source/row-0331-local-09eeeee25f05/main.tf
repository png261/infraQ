terraform {
  required_version = ">= 1.6.0"

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

resource "aws_kms_key" "postgres" {
  description             = "KMS key for PostgreSQL RDS storage encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_subnet" "db" {
  count = 2

  vpc_id            = var.vpc_id
  cidr_block        = var.db_subnet_cidr_blocks[count.index]
  availability_zone = var.db_subnet_availability_zones[count.index]

  tags = {
    Name = "benchmark-postgres-db-${count.index + 1}"
  }
}

resource "aws_security_group" "postgres" {
  name        = "benchmark-postgres-rds"
  description = "Manage PostgreSQL access to the benchmark RDS instance"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL client access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.postgres_allowed_cidr_blocks
  }

  egress {
    description = "Allow outbound responses"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "benchmark-postgres-rds"
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "benchmark-postgres-subnet-group"
  subnet_ids = aws_subnet.db[*].id

  tags = {
    Name = "benchmark-postgres-subnet-group"
  }
}

resource "aws_db_parameter_group" "postgres" {
  name        = "benchmark-postgres15-params"
  family      = "postgres15"
  description = "Custom PostgreSQL 15 parameters for benchmark RDS instance"

  parameter {
    name  = "password_encryption"
    value = "scram-sha-256"
  }

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "benchmark-postgres-15"

  allocated_storage      = 50
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  port                   = 5432
  multi_az               = true
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.postgres.arn
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  parameter_group_name   = aws_db_parameter_group.postgres.name
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false

  tags = {
    Name = "benchmark-postgres-15"
  }
}
