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

resource "aws_vpc" "airbyte" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "airbyte-rds-test-vpc"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.airbyte.id
  cidr_block              = "10.42.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "airbyte-rds-test-public-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.airbyte.id
  cidr_block              = "10.42.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "airbyte-rds-test-private-b"
  }
}

resource "aws_security_group" "rds" {
  name        = "airbyte-rds-test-postgres"
  description = "Restrict PostgreSQL access to the Airbyte test VPC only"
  vpc_id      = aws_vpc.airbyte.id

  ingress {
    description = "PostgreSQL from within the VPC only"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.airbyte.cidr_block]
  }

  egress {
    description = "Allow outbound traffic for managed RDS operations"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "airbyte-rds-test-postgres"
  }
}

resource "aws_db_subnet_group" "airbyte" {
  name       = "airbyte-rds-test-subnets"
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "airbyte-rds-test-subnets"
  }
}

resource "aws_db_parameter_group" "postgres" {
  name        = "airbyte-rds-test-postgres12"
  family      = "postgres12"
  description = "Managed PostgreSQL parameter group for Airbyte connector tests"

  tags = {
    Name = "airbyte-rds-test-postgres12"
  }
}

resource "aws_db_instance" "airbyte" {
  identifier = "airbyte-rds-test-postgres"

  allocated_storage       = 20
  engine                  = "postgres"
  engine_version          = "12.6"
  instance_class          = "db.t3.micro"
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.airbyte.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  parameter_group_name    = aws_db_parameter_group.postgres.name
  skip_final_snapshot     = true
  apply_immediately       = true
  publicly_accessible     = false
  backup_retention_period = 0
  deletion_protection     = false

  tags = {
    Name = "airbyte-rds-test-postgres"
  }
}
