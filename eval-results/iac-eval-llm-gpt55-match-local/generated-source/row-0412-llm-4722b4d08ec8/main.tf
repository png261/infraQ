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
  description = "AWS region where the RDS database and replica will be created."
  type        = string
  default     = "us-east-1"
}

variable "db_name" {
  description = "Initial database name for the primary RDS instance."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the primary RDS instance."
  type        = string
  default     = "adminuser"
}

variable "db_instance_class" {
  description = "Instance class for both the primary and replica RDS instances."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB for the primary RDS instance."
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

resource "random_password" "db_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_db_subnet_group" "main" {
  name       = "mysql-primary-replica-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "mysql-primary-replica-subnet-group"
  }
}

resource "aws_security_group" "rds" {
  name        = "mysql-primary-replica-sg"
  description = "Security group for MySQL RDS primary and replica"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow MySQL traffic from within the default VPC"
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
    Name = "mysql-primary-replica-sg"
  }
}

resource "aws_db_instance" "primary" {
  identifier = "mysql-primary-db"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  deletion_protection = false
  skip_final_snapshot = true

  apply_immediately = true

  tags = {
    Name = "mysql-primary-db"
    Role = "primary"
  }
}

resource "aws_db_instance" "replica" {
  identifier = "mysql-read-replica-db"

  replicate_source_db = aws_db_instance.primary.identifier

  instance_class = var.db_instance_class

  storage_type      = "gp3"
  storage_encrypted = true

  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 0

  deletion_protection = false
  skip_final_snapshot = true

  apply_immediately = true

  depends_on = [
    aws_db_instance.primary
  ]

  tags = {
    Name = "mysql-read-replica-db"
    Role = "replica"
  }
}

output "primary_db_endpoint" {
  description = "Endpoint of the primary MySQL RDS instance."
  value       = aws_db_instance.primary.endpoint
}

output "replica_db_endpoint" {
  description = "Endpoint of the MySQL read replica."
  value       = aws_db_instance.replica.endpoint
}

output "db_username" {
  description = "Database master username."
  value       = var.db_username
}

output "db_password" {
  description = "Database master password."
  value       = random_password.db_password.result
  sensitive   = true
}