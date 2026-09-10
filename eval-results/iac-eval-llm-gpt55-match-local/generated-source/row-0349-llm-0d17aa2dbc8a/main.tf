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
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the custom VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidr_1" {
  description = "CIDR block for the first private subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr_2" {
  description = "CIDR block for the second private subnet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "db_identifier" {
  description = "Identifier for the PostgreSQL RDS instance."
  type        = string
  default     = "custom-postgres-db"
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the PostgreSQL database."
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "Master password for the PostgreSQL database."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}

variable "postgres_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.3"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum allocated storage in GB for storage autoscaling."
  type        = number
  default     = 100
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "postgres-custom-vpc"
  }
}

resource "aws_subnet" "private_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr_1
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "postgres-private-subnet-1"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr_2
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "postgres-private-subnet-2"
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "postgres-private-subnet-group"
  subnet_ids = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id
  ]

  tags = {
    Name = "postgres-private-subnet-group"
  }
}

resource "aws_security_group" "postgres" {
  name        = "postgres-rds-security-group"
  description = "Allow PostgreSQL access only from within the custom VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "PostgreSQL from within VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "postgres-rds-security-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = var.db_identifier

  engine         = "postgres"
  engine_version = var.postgres_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]

  publicly_accessible = false
  multi_az            = false

  allow_major_version_upgrade = true
  auto_minor_version_upgrade  = true
  apply_immediately           = true

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  deletion_protection = false
  skip_final_snapshot = true

  tags = {
    Name = "custom-postgres-rds"
  }
}

output "vpc_id" {
  description = "ID of the custom VPC."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id
  ]
}

output "db_endpoint" {
  description = "PostgreSQL RDS endpoint."
  value       = aws_db_instance.postgres.endpoint
}

output "db_port" {
  description = "PostgreSQL RDS port."
  value       = aws_db_instance.postgres.port
}