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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "db_name" {
  description = "Name of the initial database to create."
  type        = string
  default     = "autoscalingdb"
}

variable "db_username" {
  description = "Master username for the RDS database."
  type        = string
  default     = "dbadmin"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "database_vpc" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "database-autoscaling-vpc"
  }
}

resource "aws_subnet" "database_subnet_a" {
  vpc_id            = aws_vpc.database_vpc.id
  cidr_block        = "10.20.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "database-autoscaling-subnet-a"
  }
}

resource "aws_subnet" "database_subnet_b" {
  vpc_id            = aws_vpc.database_vpc.id
  cidr_block        = "10.20.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "database-autoscaling-subnet-b"
  }
}

resource "aws_db_subnet_group" "database_subnet_group" {
  name = "database-autoscaling-subnet-group"

  subnet_ids = [
    aws_subnet.database_subnet_a.id,
    aws_subnet.database_subnet_b.id
  ]

  tags = {
    Name = "database-autoscaling-subnet-group"
  }
}

resource "aws_security_group" "database_security_group" {
  name        = "database-autoscaling-security-group"
  description = "Security group for RDS database with storage autoscaling"
  vpc_id      = aws_vpc.database_vpc.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "database-autoscaling-security-group"
  }
}

resource "aws_db_instance" "autoscaling_database" {
  identifier = "autoscaling-mysql-database"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  db_name  = var.db_name
  username = var.db_username

  manage_master_user_password = true

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp2"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.database_subnet_group.name
  vpc_security_group_ids = [aws_security_group.database_security_group.id]

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  deletion_protection = false
  skip_final_snapshot = true

  auto_minor_version_upgrade = true

  tags = {
    Name = "autoscaling-mysql-database"
  }
}

output "database_endpoint" {
  description = "RDS database endpoint."
  value       = aws_db_instance.autoscaling_database.endpoint
}

output "database_port" {
  description = "RDS database port."
  value       = aws_db_instance.autoscaling_database.port
}

output "master_user_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing the managed master password."
  value       = aws_db_instance.autoscaling_database.master_user_secret[0].secret_arn
}