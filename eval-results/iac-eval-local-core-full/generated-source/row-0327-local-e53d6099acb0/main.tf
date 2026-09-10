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

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "benchmark-vpc"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "benchmark-public-a"
    Tier = "public"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "benchmark-public-b"
    Tier = "public"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.101.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "benchmark-private-a"
    Tier = "private"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.102.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "benchmark-private-b"
    Tier = "private"
  }
}

resource "aws_security_group" "master" {
  name        = "benchmark-master-sg"
  description = "Master nodes management access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from inside VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "benchmark-master-sg"
  }
}

resource "aws_security_group" "worker" {
  name        = "benchmark-worker-sg"
  description = "Worker nodes application access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Application traffic from master"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.master.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "benchmark-worker-sg"
  }
}

resource "aws_security_group" "alert" {
  name        = "benchmark-alert-sg"
  description = "Alerting service access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Alert manager from workers"
    from_port       = 9093
    to_port         = 9093
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }

  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "benchmark-alert-sg"
  }
}

resource "aws_security_group" "api" {
  name        = "benchmark-api-sg"
  description = "API service HTTP access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from public clients"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from public clients"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "benchmark-api-sg"
  }
}

resource "aws_security_group" "standalone" {
  name        = "benchmark-standalone-sg"
  description = "Standalone host access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from inside VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "benchmark-standalone-sg"
  }
}

resource "aws_security_group" "database" {
  name        = "benchmark-database-sg"
  description = "PostgreSQL database access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from API service"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.api.id]
  }

  ingress {
    description     = "PostgreSQL from standalone host"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.standalone.id]
  }

  egress {
    description = "All outbound within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = {
    Name = "benchmark-database-sg"
  }
}

resource "aws_db_subnet_group" "database" {
  name       = "benchmark-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "benchmark-db-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier             = "benchmark-postgres-17-1"
  allocated_storage      = 5
  engine                 = "postgres"
  engine_version         = "17.1"
  instance_class         = "db.t4g.micro"
  db_name                = "benchmark"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.database.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}
