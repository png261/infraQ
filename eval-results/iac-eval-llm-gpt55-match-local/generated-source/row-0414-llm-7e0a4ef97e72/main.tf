terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the RDS instance will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the RDS instance."
  type        = string
  default     = "dbadmin"
}

variable "allowed_cidr" {
  description = "CIDR block allowed to connect to the RDS instance on port 3306."
  type        = string
  default     = "0.0.0.0/0"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "random_password" "db_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_security_group" "rds" {
  name        = "basic-rds-mysql-sg"
  description = "Security group for basic RDS MySQL instance"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow MySQL access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "basic-rds-mysql-sg"
  }
}

resource "aws_db_subnet_group" "default" {
  name       = "basic-rds-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "basic-rds-subnet-group"
  }
}

resource "aws_db_instance" "basic" {
  identifier = "basic-gp3-rds-instance"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = true
  multi_az            = false

  backup_retention_period = 0
  deletion_protection     = false
  skip_final_snapshot     = true

  auto_minor_version_upgrade = true

  tags = {
    Name = "basic-gp3-rds-instance"
  }
}

output "rds_endpoint" {
  description = "RDS instance endpoint."
  value       = aws_db_instance.basic.endpoint
}

output "rds_port" {
  description = "RDS instance port."
  value       = aws_db_instance.basic.port
}

output "db_name" {
  description = "Database name."
  value       = aws_db_instance.basic.db_name
}

output "db_username" {
  description = "Database master username."
  value       = var.db_username
}

output "db_password" {
  description = "Generated database password."
  value       = random_password.db_password.result
  sensitive   = true
}