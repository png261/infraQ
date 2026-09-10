terraform {
  required_version = ">= 1.3.0"

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

provider "random" {}

variable "aws_region" {
  description = "AWS region where the RDS MySQL instance will be created."
  type        = string
  default     = "us-east-1"
}

variable "db_instance_identifier" {
  description = "Identifier for the RDS MySQL database instance."
  type        = string
  default     = "public-mysql-db"
}

variable "db_name" {
  description = "Initial database name to create."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the MySQL database."
  type        = string
  default     = "adminuser"
}

variable "db_instance_class" {
  description = "Instance class for the RDS MySQL instance."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage size in GB."
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

resource "aws_security_group" "rds_public_sg" {
  name        = "public-rds-mysql-sg"
  description = "Allow public inbound MySQL access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow MySQL access from the internet"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "public-rds-mysql-sg"
  }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name        = "public-mysql-db-subnet-group"
  description = "DB subnet group using default VPC subnets"
  subnet_ids  = data.aws_subnets.default.ids

  tags = {
    Name = "public-mysql-db-subnet-group"
  }
}

resource "aws_db_instance" "mysql" {
  identifier = var.db_instance_identifier

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

  port = 3306

  publicly_accessible    = true
  vpc_security_group_ids = [aws_security_group.rds_public_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  multi_az               = false
  auto_minor_version_upgrade = true
  deletion_protection    = false
  skip_final_snapshot    = true

  apply_immediately = true

  tags = {
    Name = "public-mysql-db"
  }
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint."
  value       = aws_db_instance.mysql.endpoint
}

output "rds_address" {
  description = "RDS MySQL hostname."
  value       = aws_db_instance.mysql.address
}

output "rds_port" {
  description = "RDS MySQL port."
  value       = aws_db_instance.mysql.port
}

output "database_name" {
  description = "Initial database name."
  value       = aws_db_instance.mysql.db_name
}

output "database_username" {
  description = "Master database username."
  value       = var.db_username
}

output "database_password" {
  description = "Generated master database password."
  value       = random_password.db_password.result
  sensitive   = true
}