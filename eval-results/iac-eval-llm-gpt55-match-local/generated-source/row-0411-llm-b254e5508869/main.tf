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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "db_name" {
  description = "Initial MySQL database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the MySQL database."
  type        = string
  default     = "adminuser"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for the RDS instance in GB."
  type        = number
  default     = 20
}

variable "mysql_engine_version" {
  description = "MySQL engine version."
  type        = string
  default     = "8.0"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_password" "db_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "mysql-rds-vpc"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.40.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "mysql-rds-private-subnet-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.40.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "mysql-rds-private-subnet-b"
  }
}

resource "aws_db_subnet_group" "mysql" {
  name       = "mysql-rds-subnet-group"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = {
    Name = "mysql-rds-subnet-group"
  }
}

resource "aws_security_group" "mysql" {
  name        = "mysql-rds-security-group"
  description = "Allow MySQL access from within the VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow MySQL traffic from VPC CIDR"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mysql-rds-security-group"
  }
}

resource "aws_db_instance" "mysql" {
  identifier = "mysql-instance-skip-final-snapshot"

  engine         = "mysql"
  engine_version = var.mysql_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  port = 3306

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.mysql.id]

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  auto_minor_version_upgrade = true
  deletion_protection        = false

  skip_final_snapshot = true

  tags = {
    Name = "mysql-instance-skip-final-snapshot"
  }
}

output "rds_endpoint" {
  description = "The connection endpoint for the MySQL RDS instance."
  value       = aws_db_instance.mysql.endpoint
}

output "rds_database_name" {
  description = "The initial database name."
  value       = aws_db_instance.mysql.db_name
}

output "rds_username" {
  description = "The master username."
  value       = aws_db_instance.mysql.username
}

output "rds_password" {
  description = "The generated master password."
  value       = random_password.db_password.result
  sensitive   = true
}