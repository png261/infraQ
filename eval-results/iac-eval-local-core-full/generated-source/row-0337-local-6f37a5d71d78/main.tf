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

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "airbyte_tests" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "airbyte-rds-tests-vpc"
  }
}

resource "aws_internet_gateway" "airbyte_tests" {
  vpc_id = aws_vpc.airbyte_tests.id

  tags = {
    Name = "airbyte-rds-tests-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.airbyte_tests.id
  cidr_block              = var.public_subnet_cidr_block
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "airbyte-rds-tests-public-subnet"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.airbyte_tests.id
  cidr_block        = var.private_subnet_cidr_block
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "airbyte-rds-tests-private-subnet"
    Tier = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.airbyte_tests.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.airbyte_tests.id
  }

  tags = {
    Name = "airbyte-rds-tests-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_db_subnet_group" "airbyte_tests" {
  name       = "airbyte-rds-tests-subnet-group"
  subnet_ids = [aws_subnet.public.id, aws_subnet.private.id]

  tags = {
    Name = "airbyte-rds-tests-subnet-group"
  }
}

resource "aws_security_group" "postgres" {
  name        = "airbyte-rds-tests-postgres-sg"
  description = "Allow PostgreSQL only from inside the Airbyte test VPC"
  vpc_id      = aws_vpc.airbyte_tests.id

  ingress {
    description = "PostgreSQL from VPC CIDR only"
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
    Name = "airbyte-rds-tests-postgres-sg"
  }
}

resource "aws_db_parameter_group" "postgres15" {
  name        = "airbyte-rds-tests-postgres15"
  family      = "postgres15"
  description = "Managed PostgreSQL 15 parameter group for Airbyte connector tests"

  tags = {
    Name = "airbyte-rds-tests-postgres15"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "airbyte-rds-tests-postgres15"

  allocated_storage          = 500
  storage_type               = "gp3"
  engine                     = "postgres"
  engine_version             = "15"
  instance_class             = var.db_instance_class
  username                   = var.db_username
  password                   = var.db_password
  db_subnet_group_name       = aws_db_subnet_group.airbyte_tests.name
  vpc_security_group_ids     = [aws_security_group.postgres.id]
  parameter_group_name       = aws_db_parameter_group.postgres15.name
  publicly_accessible        = false
  auto_minor_version_upgrade = true
  backup_retention_period    = 7
  deletion_protection        = false
  skip_final_snapshot        = true

  tags = {
    Name = "airbyte-rds-tests-postgres15"
  }
}
