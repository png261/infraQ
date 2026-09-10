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
    Name        = "benchmark-main-vpc"
    Environment = "dev-benchmark"
  }
}

resource "aws_subnet" "db_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "benchmark-db-subnet-a"
    Environment = "dev-benchmark"
  }
}

resource "aws_subnet" "db_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name        = "benchmark-db-subnet-b"
    Environment = "dev-benchmark"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "benchmark-main-igw"
    Environment = "dev-benchmark"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "benchmark-public-rt"
    Environment = "dev-benchmark"
  }
}

resource "aws_route_table_association" "db_a" {
  subnet_id      = aws_subnet.db_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "db_b" {
  subnet_id      = aws_subnet.db_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "database" {
  name        = "benchmark-postgres-access"
  description = "Allow PostgreSQL access for benchmark RDS instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "PostgreSQL access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.database_access_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "benchmark-postgres-sg"
    Environment = "dev-benchmark"
  }
}

resource "aws_db_subnet_group" "database" {
  name       = "benchmark-postgres-subnet-group"
  subnet_ids = [aws_subnet.db_a.id, aws_subnet.db_b.id]

  tags = {
    Name        = "benchmark-postgres-subnet-group"
    Environment = "dev-benchmark"
  }
}

resource "aws_db_instance" "postgres" {
  identifier             = "benchmark-postgres-153"
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "15.3"
  instance_class         = "db.t4g.micro"
  storage_type           = "gp2"
  db_name                = "benchmarkdb"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.database.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = true
  skip_final_snapshot    = true

  tags = {
    Name        = "benchmark-postgres-153"
    Environment = "dev-benchmark"
  }
}
