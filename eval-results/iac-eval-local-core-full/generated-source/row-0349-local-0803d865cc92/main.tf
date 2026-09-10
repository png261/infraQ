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

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "benchmark-postgres-vpc"
  }
}

resource "aws_subnet" "database" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "benchmark-postgres-subnet"
  }
}

resource "aws_subnet" "database_secondary" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "benchmark-postgres-subnet-secondary"
  }
}

resource "aws_db_subnet_group" "database" {
  name = "benchmark-postgres-subnet-group"
  subnet_ids = [
    aws_subnet.database.id,
    aws_subnet.database_secondary.id,
  ]

  tags = {
    Name = "benchmark-postgres-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "benchmark-postgres-db"

  allocated_storage = var.allocated_storage
  engine            = "postgres"
  engine_version    = var.engine_version
  instance_class    = var.instance_class

  db_name  = var.database_name
  username = var.database_username
  password = var.database_password

  db_subnet_group_name = aws_db_subnet_group.database.name

  allow_major_version_upgrade = true
  auto_minor_version_upgrade  = true
  publicly_accessible         = false

  skip_final_snapshot = true
  deletion_protection = false
}
