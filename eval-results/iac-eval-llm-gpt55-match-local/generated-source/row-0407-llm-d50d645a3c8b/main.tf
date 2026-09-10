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
  description = "Name of the initial database to create."
  type        = string
  default     = "basicdb"
}

variable "db_username" {
  description = "Master username for the RDS database."
  type        = string
  default     = "adminuser"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "allowed_mysql_cidr" {
  description = "CIDR block allowed to connect to MySQL. For production, restrict this to your IP."
  type        = string
  default     = "0.0.0.0/0"
}

resource "random_password" "db_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "basic-sql-db-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "basic-sql-db-igw"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "basic-sql-db-public-subnet-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "basic-sql-db-public-subnet-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "basic-sql-db-public-route-table"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "rds" {
  name        = "basic-sql-db-security-group"
  description = "Allow MySQL access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow MySQL inbound access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.allowed_mysql_cidr]
  }

  egress {
    description = "Allow all outbound access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "basic-sql-db-security-group"
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "basic-sql-db-subnet-group"
  subnet_ids = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  tags = {
    Name = "basic-sql-db-subnet-group"
  }
}

resource "aws_db_instance" "mysql" {
  identifier = "basic-sql-db"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = true
  multi_az            = false

  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  auto_minor_version_upgrade = true

  tags = {
    Name = "basic-sql-db"
  }
}

output "database_endpoint" {
  description = "RDS database endpoint."
  value       = aws_db_instance.mysql.endpoint
}

output "database_port" {
  description = "RDS database port."
  value       = aws_db_instance.mysql.port
}

output "database_name" {
  description = "Initial database name."
  value       = aws_db_instance.mysql.db_name
}

output "database_username" {
  description = "Database master username."
  value       = aws_db_instance.mysql.username
}

output "database_password" {
  description = "Database master password."
  value       = random_password.db_password.result
  sensitive   = true
}