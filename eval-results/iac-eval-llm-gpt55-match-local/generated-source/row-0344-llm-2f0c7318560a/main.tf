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
  description = "Master username for the MySQL database."
  type        = string
  default     = "admin"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
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

resource "aws_security_group" "rds_public" {
  name        = "public-mysql-rds-sg"
  description = "Allow public inbound MySQL access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow MySQL from the internet"
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
    Name = "public-mysql-rds-sg"
  }
}

resource "aws_db_subnet_group" "default" {
  name        = "mysql-public-db-subnet-group"
  description = "Subnet group for public MySQL RDS instance"
  subnet_ids  = data.aws_subnets.default.ids

  tags = {
    Name = "mysql-public-db-subnet-group"
  }
}

resource "aws_db_instance" "mysql" {
  identifier = "mysql-57-public-200gb"

  engine         = "mysql"
  engine_version = "5.7"
  instance_class = "db.t3.micro"

  allocated_storage     = 200
  max_allocated_storage = 200
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds_public.id]

  publicly_accessible = true
  port                = 3306

  multi_az               = false
  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = {
    Name = "mysql-57-public-200gb"
  }
}

output "rds_endpoint" {
  description = "The connection endpoint for the MySQL RDS instance."
  value       = aws_db_instance.mysql.endpoint
}

output "rds_port" {
  description = "The port used by the MySQL RDS instance."
  value       = aws_db_instance.mysql.port
}

output "db_username" {
  description = "The master username for the MySQL database."
  value       = var.db_username
}

output "db_password" {
  description = "The randomly generated master password for the MySQL database."
  value       = random_password.db_password.result
  sensitive   = true
}