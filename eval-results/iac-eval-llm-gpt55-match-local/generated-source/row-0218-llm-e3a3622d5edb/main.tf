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
  region = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "mysql-cluster"
}

variable "mysql_database_name" {
  type    = string
  default = "appdb"
}

variable "mysql_master_username" {
  type    = string
  default = "adminuser"
}

variable "mysql_instance_class" {
  type    = string
  default = "db.m6gd.large"
}

variable "mysql_engine_version" {
  type    = string
  default = "8.0.35"
}

variable "allowed_mysql_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

resource "random_password" "mysql_master_password" {
  length  = 24
  special = false
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "private_us_east_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-us-east-1a"
  }
}

resource "aws_subnet" "private_us_east_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-us-east-1b"
  }
}

resource "aws_subnet" "private_us_east_1c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-1c"
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-us-east-1c"
  }
}

resource "aws_db_subnet_group" "mysql" {
  name = "${var.project_name}-subnet-group"

  subnet_ids = [
    aws_subnet.private_us_east_1a.id,
    aws_subnet.private_us_east_1b.id,
    aws_subnet.private_us_east_1c.id
  ]

  tags = {
    Name = "${var.project_name}-subnet-group"
  }
}

resource "aws_security_group" "mysql" {
  name        = "${var.project_name}-sg"
  description = "Security group for MySQL RDS cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow MySQL access from VPC CIDR"
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
    Name = "${var.project_name}-sg"
  }
}

resource "aws_rds_cluster" "mysql" {
  cluster_identifier = "${var.project_name}-multi-az"

  engine         = "mysql"
  engine_version = var.mysql_engine_version

  database_name   = var.mysql_database_name
  master_username = var.mysql_master_username
  master_password = random_password.mysql_master_password.result

  availability_zones = [
    "us-east-1a",
    "us-east-1b",
    "us-east-1c"
  ]

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.mysql.id]

  allocated_storage         = 100
  storage_type              = "io1"
  iops                      = 1000
  db_cluster_instance_class = var.mysql_instance_class

  port = 3306

  backup_retention_period = 7
  preferred_backup_window = "07:00-09:00"

  deletion_protection = false
  skip_final_snapshot = true

  apply_immediately = true

  tags = {
    Name = "${var.project_name}-multi-az"
  }
}

output "mysql_cluster_endpoint" {
  value = aws_rds_cluster.mysql.endpoint
}

output "mysql_cluster_reader_endpoint" {
  value = aws_rds_cluster.mysql.reader_endpoint
}

output "mysql_cluster_port" {
  value = aws_rds_cluster.mysql.port
}

output "mysql_database_name" {
  value = aws_rds_cluster.mysql.database_name
}

output "mysql_master_username" {
  value = var.mysql_master_username
}

output "mysql_master_password" {
  value     = random_password.mysql_master_password.result
  sensitive = true
}