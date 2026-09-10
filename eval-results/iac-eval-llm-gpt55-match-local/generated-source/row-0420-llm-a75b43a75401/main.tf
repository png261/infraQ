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
  description = "Initial MySQL database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the MySQL database."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the MySQL database."
  type        = string
  sensitive   = true
  default     = "ChangeMe123!"
}

variable "db_instance_identifier" {
  description = "Identifier for the RDS MySQL instance."
  type        = string
  default     = "terraform-mysql-instance"
}

variable "db_snapshot_identifier" {
  description = "Identifier for the manual RDS snapshot."
  type        = string
  default     = "terraform-mysql-instance-snapshot"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "mysql-rds-vpc"
  }
}

resource "aws_subnet" "db_subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "mysql-rds-subnet-a"
  }
}

resource "aws_subnet" "db_subnet_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "mysql-rds-subnet-b"
  }
}

resource "aws_db_subnet_group" "mysql" {
  name       = "mysql-rds-subnet-group"
  subnet_ids = [
    aws_subnet.db_subnet_a.id,
    aws_subnet.db_subnet_b.id
  ]

  tags = {
    Name = "mysql-rds-subnet-group"
  }
}

resource "aws_security_group" "mysql" {
  name        = "mysql-rds-security-group"
  description = "Security group for MySQL RDS instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow MySQL access from within the VPC"
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
  identifier = var.db_instance_identifier

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.mysql.id]

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  deletion_protection = false
  skip_final_snapshot = true

  apply_immediately = true

  tags = {
    Name = "terraform-mysql-instance"
  }
}

resource "aws_db_snapshot" "mysql_snapshot" {
  db_instance_identifier = aws_db_instance.mysql.identifier
  db_snapshot_identifier = var.db_snapshot_identifier

  tags = {
    Name = "terraform-mysql-instance-snapshot"
  }

  depends_on = [
    aws_db_instance.mysql
  ]
}

output "mysql_endpoint" {
  description = "The connection endpoint for the MySQL RDS instance."
  value       = aws_db_instance.mysql.endpoint
}

output "mysql_instance_identifier" {
  description = "The RDS MySQL instance identifier."
  value       = aws_db_instance.mysql.identifier
}

output "mysql_snapshot_identifier" {
  description = "The manual RDS snapshot identifier."
  value       = aws_db_snapshot.mysql_snapshot.id
}