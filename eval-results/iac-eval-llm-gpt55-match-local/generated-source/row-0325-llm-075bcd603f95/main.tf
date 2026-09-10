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
  description = "AWS region where the MySQL RDS instance will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "db_allocated_storage" {
  description = "Allocated storage size for the MySQL database in GB."
  type        = number
  default     = 20
}

variable "db_instance_class" {
  description = "Instance class for the MySQL RDS instance."
  type        = string
  default     = "db.t3.micro"
}

variable "db_username" {
  description = "Master username for the MySQL database."
  type        = string
  default     = "adminuser"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_string" "db_id_suffix" {
  length  = 8
  upper   = false
  lower   = true
  numeric = true
  special = false
}

resource "random_password" "db_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_vpc" "mysql_vpc" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "mysql-rds-vpc-${random_string.db_id_suffix.result}"
  }
}

resource "aws_subnet" "mysql_subnet_a" {
  vpc_id            = aws_vpc.mysql_vpc.id
  cidr_block        = "10.50.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "mysql-rds-subnet-a-${random_string.db_id_suffix.result}"
  }
}

resource "aws_subnet" "mysql_subnet_b" {
  vpc_id            = aws_vpc.mysql_vpc.id
  cidr_block        = "10.50.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "mysql-rds-subnet-b-${random_string.db_id_suffix.result}"
  }
}

resource "aws_db_subnet_group" "mysql_subnet_group" {
  name = "mysql-subnet-group-${random_string.db_id_suffix.result}"

  subnet_ids = [
    aws_subnet.mysql_subnet_a.id,
    aws_subnet.mysql_subnet_b.id
  ]

  tags = {
    Name = "mysql-rds-subnet-group-${random_string.db_id_suffix.result}"
  }
}

resource "aws_security_group" "mysql_sg" {
  name        = "mysql-rds-sg-${random_string.db_id_suffix.result}"
  description = "Security group for MySQL RDS instance"
  vpc_id      = aws_vpc.mysql_vpc.id

  ingress {
    description = "Allow MySQL traffic from within the VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.mysql_vpc.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mysql-rds-sg-${random_string.db_id_suffix.result}"
  }
}

resource "aws_db_instance" "mysql" {
  identifier = "mysql-${random_string.db_id_suffix.result}"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"

  db_name  = "appdb"
  username = var.db_username
  password = random_password.db_password.result

  port = 3306

  db_subnet_group_name   = aws_db_subnet_group.mysql_subnet_group.name
  vpc_security_group_ids = [aws_security_group.mysql_sg.id]

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  apply_immediately = true

  tags = {
    Name = "mysql-rds-${random_string.db_id_suffix.result}"
  }
}

output "db_identifier" {
  description = "Randomly generated RDS MySQL database identifier."
  value       = aws_db_instance.mysql.identifier
}

output "db_endpoint" {
  description = "RDS MySQL database endpoint."
  value       = aws_db_instance.mysql.endpoint
}

output "db_port" {
  description = "RDS MySQL database port."
  value       = aws_db_instance.mysql.port
}

output "db_name" {
  description = "Initial MySQL database name."
  value       = aws_db_instance.mysql.db_name
}

output "db_username" {
  description = "Master username for the MySQL database."
  value       = aws_db_instance.mysql.username
}

output "db_password" {
  description = "Randomly generated master password for the MySQL database."
  value       = random_password.db_password.result
  sensitive   = true
}