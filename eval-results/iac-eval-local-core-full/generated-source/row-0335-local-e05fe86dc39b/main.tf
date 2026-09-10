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

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.airbyte.id
  cidr_block              = "10.42.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "airbyte-rds-public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.airbyte.id
  cidr_block        = "10.42.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "airbyte-rds-private-subnet"
  }
}

resource "aws_security_group" "rds" {
  name        = "airbyte-rds-postgres-sg"
  description = "Restrict PostgreSQL access to traffic from within the VPC only"
  vpc_id      = aws_vpc.airbyte.id

  ingress {
    description = "PostgreSQL from VPC CIDR only"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.airbyte.cidr_block]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "airbyte-rds-postgres-sg"
  }
}

resource "aws_db_subnet_group" "airbyte" {
  name       = "airbyte-rds-subnet-group"
  subnet_ids = [aws_subnet.public.id, aws_subnet.private.id]

  tags = {
    Name = "airbyte-rds-subnet-group"
  }
}

resource "aws_db_parameter_group" "postgres" {
  name        = "airbyte-postgres12-params"
  family      = "postgres12"
  description = "Managed PostgreSQL 12 parameter group for Airbyte connector tests"
}

resource "aws_db_instance" "airbyte" {
  identifier             = "airbyte-connector-test-postgres"
  allocated_storage      = 5
  engine                 = "postgres"
  engine_version         = "12.6"
  instance_class         = "db.t3.micro"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.airbyte.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgres.name
  publicly_accessible    = false
  skip_final_snapshot    = true
}
