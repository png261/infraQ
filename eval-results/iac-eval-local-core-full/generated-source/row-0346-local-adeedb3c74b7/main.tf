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
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "benchmark-postgres-subnet-a"
  }
}

resource "aws_db_subnet_group" "database" {
  name = "benchmark-postgres-subnet-group"
  subnet_ids = [
    aws_subnet.database.id,
  ]

  tags = {
    Name = "benchmark-postgres-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier              = "benchmark-postgres-db"
  allocated_storage       = 20
  engine                  = "postgres"
  engine_version          = "16.3"
  instance_class          = "db.t3.micro"
  db_name                 = "benchmarkdb"
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.database.name
  skip_final_snapshot     = true
  publicly_accessible     = false
  storage_encrypted       = true
  backup_retention_period = 0
}
