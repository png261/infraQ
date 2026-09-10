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
  description = "AWS region where the RDS instance will be created."
  type        = string
  default     = "us-east-1"
}

variable "db_username" {
  description = "Master username for the RDS database."
  type        = string
  default     = "adminuser"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GB."
  type        = number
  default     = 20
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

resource "random_id" "rds_identifier" {
  byte_length = 4
}

resource "random_password" "rds_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-mysql-sg-${random_id.rds_identifier.hex}"
  description = "Security group for RDS MySQL instance"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow MySQL access from within the default VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-mysql-sg-${random_id.rds_identifier.hex}"
  }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group-${random_id.rds_identifier.hex}"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "rds-subnet-group-${random_id.rds_identifier.hex}"
  }
}

resource "aws_db_instance" "mysql" {
  identifier = "mysql-rds-${random_id.rds_identifier.hex}"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.rds_password.result

  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  deletion_protection = false
  skip_final_snapshot = true

  apply_immediately = true

  tags = {
    Name = "mysql-rds-${random_id.rds_identifier.hex}"
  }
}

output "rds_identifier" {
  description = "Randomly generated RDS instance identifier."
  value       = aws_db_instance.mysql.identifier
}

output "rds_endpoint" {
  description = "RDS database endpoint."
  value       = aws_db_instance.mysql.endpoint
}

output "rds_database_name" {
  description = "Initial database name."
  value       = aws_db_instance.mysql.db_name
}

output "rds_username" {
  description = "RDS master username."
  value       = aws_db_instance.mysql.username
}

output "rds_password" {
  description = "Randomly generated RDS master password."
  value       = random_password.rds_password.result
  sensitive   = true
}