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
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "db_name" {
  description = "Name of the PostgreSQL database."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the PostgreSQL database."
  type        = string
  default     = "postgresadmin"
}

variable "db_password" {
  description = "Master password for the PostgreSQL database."
  type        = string
  sensitive   = true
  default     = "ChangeMe123456789!"
}

variable "allowed_db_cidr" {
  description = "CIDR block allowed to connect to PostgreSQL. For production, restrict this to a trusted IP range."
  type        = string
  default     = "0.0.0.0/0"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-postgres-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-postgres-igw"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "postgres-public-subnet-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "postgres-public-subnet-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "postgres-public-route-table"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "postgres" {
  name        = "postgres-rds-sg"
  description = "Allow PostgreSQL database access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow PostgreSQL access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.allowed_db_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "postgres-rds-security-group"
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "postgres-rds-subnet-group"
  subnet_ids = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  tags = {
    Name = "postgres-rds-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "postgres-15-3-public-db"

  engine         = "postgres"
  engine_version = "15.3"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  port = 5432

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]

  publicly_accessible = true
  multi_az            = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  skip_final_snapshot = true
  deletion_protection = false

  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = {
    Name = "postgres-15-3-public-rds"
  }
}

output "database_endpoint" {
  description = "The PostgreSQL RDS endpoint for connectivity."
  value       = aws_db_instance.postgres.endpoint
}

output "database_port" {
  description = "The PostgreSQL database port."
  value       = aws_db_instance.postgres.port
}

output "database_name" {
  description = "The PostgreSQL database name."
  value       = aws_db_instance.postgres.db_name
}

output "database_username" {
  description = "The PostgreSQL master username."
  value       = aws_db_instance.postgres.username
}