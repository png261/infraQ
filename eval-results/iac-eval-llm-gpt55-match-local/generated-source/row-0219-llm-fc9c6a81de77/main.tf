terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the MySQL RDS instance will be created."
  type        = string
  default     = "us-east-1"
}

variable "db_instance_identifier" {
  description = "Identifier for the RDS MySQL instance."
  type        = string
  default     = "example-mysql-instance"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "exampledb"
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

variable "allocated_storage" {
  description = "Allocated storage in GB."
  type        = number
  default     = 20
}

variable "mysql_engine_version" {
  description = "MySQL engine version."
  type        = string
  default     = "8.0"
}

variable "allowed_mysql_cidr" {
  description = "CIDR block allowed to connect to MySQL. Change this for production use."
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

resource "aws_security_group" "mysql_sg" {
  name        = "mysql-rds-security-group"
  description = "Allow inbound MySQL traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow MySQL access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.allowed_mysql_cidr]
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

resource "aws_db_subnet_group" "mysql_subnet_group" {
  name       = "mysql-rds-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "mysql-rds-subnet-group"
  }
}

resource "aws_db_instance" "mysql" {
  identifier = var.db_instance_identifier

  engine         = "mysql"
  engine_version = var.mysql_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  port = 3306

  db_subnet_group_name   = aws_db_subnet_group.mysql_subnet_group.name
  vpc_security_group_ids = [aws_security_group.mysql_sg.id]

  publicly_accessible = true
  multi_az            = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  deletion_protection = false
  skip_final_snapshot = true

  auto_minor_version_upgrade = true

  tags = {
    Name = "example-mysql-instance"
  }
}

output "mysql_endpoint" {
  description = "The connection endpoint for the MySQL RDS instance."
  value       = aws_db_instance.mysql.endpoint
}

output "mysql_port" {
  description = "The MySQL database port."
  value       = aws_db_instance.mysql.port
}

output "mysql_database_name" {
  description = "The initial database name."
  value       = aws_db_instance.mysql.db_name
}

output "mysql_username" {
  description = "The master username for the MySQL database."
  value       = aws_db_instance.mysql.username
}

output "mysql_password" {
  description = "The generated master password for the MySQL database."
  value       = random_password.db_password.result
  sensitive   = true
}