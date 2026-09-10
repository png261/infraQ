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

provider "random" {}

variable "aws_region" {
  description = "AWS region where the RDS MySQL instance will be created."
  type        = string
  default     = "us-east-1"
}

variable "db_identifier" {
  description = "Identifier for the RDS MySQL database instance."
  type        = string
  default     = "public-mysql-rds-instance"
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
  description = "Instance class for the RDS MySQL database."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage size in GB."
  type        = number
  default     = 20
}

variable "mysql_port" {
  description = "MySQL database port."
  type        = number
  default     = 3306
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
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_id" "final_snapshot_suffix" {
  byte_length = 4
}

resource "aws_security_group" "rds_public_mysql" {
  name        = "${var.db_identifier}-public-mysql-sg"
  description = "Public security group allowing MySQL access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow public MySQL access"
    from_port   = var.mysql_port
    to_port     = var.mysql_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description      = "Allow public IPv6 MySQL access"
    from_port        = var.mysql_port
    to_port          = var.mysql_port
    protocol         = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "Allow all outbound IPv4 traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.db_identifier}-public-mysql-sg"
  }
}

resource "aws_db_subnet_group" "mysql" {
  name        = "${var.db_identifier}-subnet-group"
  description = "DB subnet group for public MySQL RDS instance"
  subnet_ids  = data.aws_subnets.default.ids

  tags = {
    Name = "${var.db_identifier}-subnet-group"
  }
}

resource "aws_db_instance" "mysql" {
  identifier = var.db_identifier

  engine = "mysql"

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result
  port     = var.mysql_port

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.rds_public_mysql.id]

  publicly_accessible = true
  multi_az            = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  deletion_protection = false

  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.db_identifier}-final-${random_id.final_snapshot_suffix.hex}"

  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = {
    Name = var.db_identifier
  }
}

output "rds_endpoint" {
  description = "Public endpoint of the RDS MySQL instance."
  value       = aws_db_instance.mysql.endpoint
}

output "rds_port" {
  description = "Port used by the RDS MySQL instance."
  value       = aws_db_instance.mysql.port
}

output "rds_database_name" {
  description = "Initial database name."
  value       = aws_db_instance.mysql.db_name
}

output "rds_username" {
  description = "Master username for the RDS MySQL instance."
  value       = aws_db_instance.mysql.username
}

output "rds_password" {
  description = "Randomly generated master password for the RDS MySQL instance."
  value       = random_password.db_password.result
  sensitive   = true
}