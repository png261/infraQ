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

locals {
  name_prefix = "secure-postgres"
}

resource "aws_subnet" "database_a" {
  vpc_id                  = var.vpc_id
  cidr_block              = var.database_subnet_cidr_blocks[0]
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-db-a"
  }
}

resource "aws_subnet" "database_b" {
  vpc_id                  = var.vpc_id
  cidr_block              = var.database_subnet_cidr_blocks[1]
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-db-b"
  }
}

resource "aws_security_group" "postgres" {
  name        = "${local.name_prefix}-sg"
  description = "Manage PostgreSQL access to the RDS instance"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL access from allowed CIDR blocks"
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
    Name = "${local.name_prefix}-sg"
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${local.name_prefix}-subnet-group"
  subnet_ids = [aws_subnet.database_a.id, aws_subnet.database_b.id]

  tags = {
    Name = "${local.name_prefix}-subnet-group"
  }
}

resource "aws_db_parameter_group" "postgres" {
  name        = "${local.name_prefix}-pg15"
  family      = "postgres15"
  description = "Custom PostgreSQL parameter group enforcing encrypted passwords and SSL"

  parameter {
    name  = "password_encryption"
    value = "scram-sha-256"
  }

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

resource "aws_kms_key" "postgres" {
  description             = "KMS key for PostgreSQL RDS storage encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${local.name_prefix}-kms"
  }
}

resource "aws_db_instance" "postgres" {
  identifier                  = "${local.name_prefix}-db"
  allocated_storage           = var.allocated_storage
  engine                      = "postgres"
  engine_version              = var.postgres_engine_version
  instance_class              = "db.t3.micro"
  db_name                     = var.database_name
  username                    = var.database_username
  password                    = var.database_password
  backup_retention_period     = 7
  allow_major_version_upgrade = true
  multi_az                    = var.enable_multi_az
  storage_encrypted           = true
  kms_key_id                  = aws_kms_key.postgres.arn
  db_subnet_group_name        = aws_db_subnet_group.postgres.name
  vpc_security_group_ids      = [aws_security_group.postgres.id]
  parameter_group_name        = aws_db_parameter_group.postgres.name
  publicly_accessible         = false
  skip_final_snapshot         = true
  deletion_protection         = false

  tags = {
    Name = "${local.name_prefix}-db"
  }
}
