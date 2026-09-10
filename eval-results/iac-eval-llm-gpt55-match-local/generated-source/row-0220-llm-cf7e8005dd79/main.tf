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
  description = "AWS region where the PostgreSQL RDS instance will be created."
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
  default     = "ChangeMe12345!"
}

variable "db_instance_class" {
  description = "Instance class for the PostgreSQL RDS instance."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GB for the PostgreSQL RDS instance."
  type        = number
  default     = 20
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "postgres_vpc" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "postgres-rds-vpc"
  }
}

resource "aws_internet_gateway" "postgres_igw" {
  vpc_id = aws_vpc.postgres_vpc.id

  tags = {
    Name = "postgres-rds-igw"
  }
}

resource "aws_subnet" "postgres_subnet_a" {
  vpc_id                  = aws_vpc.postgres_vpc.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "postgres-rds-subnet-a"
  }
}

resource "aws_subnet" "postgres_subnet_b" {
  vpc_id                  = aws_vpc.postgres_vpc.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "postgres-rds-subnet-b"
  }
}

resource "aws_route_table" "postgres_public_rt" {
  vpc_id = aws_vpc.postgres_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.postgres_igw.id
  }

  tags = {
    Name = "postgres-rds-public-route-table"
  }
}

resource "aws_route_table_association" "postgres_subnet_a_assoc" {
  subnet_id      = aws_subnet.postgres_subnet_a.id
  route_table_id = aws_route_table.postgres_public_rt.id
}

resource "aws_route_table_association" "postgres_subnet_b_assoc" {
  subnet_id      = aws_subnet.postgres_subnet_b.id
  route_table_id = aws_route_table.postgres_public_rt.id
}

resource "aws_security_group" "postgres_sg" {
  name        = "postgres-rds-security-group"
  description = "Allow PostgreSQL access from within the VPC"
  vpc_id      = aws_vpc.postgres_vpc.id

  ingress {
    description = "PostgreSQL from VPC CIDR"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.postgres_vpc.cidr_block]
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

resource "aws_db_subnet_group" "postgres_subnet_group" {
  name       = "postgres-rds-subnet-group"
  subnet_ids = [
    aws_subnet.postgres_subnet_a.id,
    aws_subnet.postgres_subnet_b.id
  ]

  tags = {
    Name = "postgres-rds-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "postgresql-instance"

  engine         = "postgres"
  engine_version = "16.3"

  instance_class    = var.db_instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  port = 5432

  db_subnet_group_name   = aws_db_subnet_group.postgres_subnet_group.name
  vpc_security_group_ids = [aws_security_group.postgres_sg.id]

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  auto_minor_version_upgrade = true
  deletion_protection        = false
  skip_final_snapshot        = true

  tags = {
    Name = "postgresql-instance"
  }
}

output "postgres_endpoint" {
  description = "PostgreSQL RDS endpoint."
  value       = aws_db_instance.postgres.endpoint
}

output "postgres_port" {
  description = "PostgreSQL RDS port."
  value       = aws_db_instance.postgres.port
}

output "postgres_database_name" {
  description = "PostgreSQL database name."
  value       = aws_db_instance.postgres.db_name
}

output "postgres_username" {
  description = "PostgreSQL master username."
  value       = aws_db_instance.postgres.username
  sensitive   = true
}