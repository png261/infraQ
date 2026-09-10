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

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_1_cidr" {
  description = "CIDR block for the first public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_2_cidr" {
  description = "CIDR block for the second public subnet."
  type        = string
  default     = "10.0.2.0/24"
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
  default     = "db.t4g.micro"
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
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "mysql-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "mysql-vpc-igw"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "mysql-public-subnet-1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "mysql-public-subnet-2"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "mysql-public-route-table"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "db_client" {
  name        = "mysql-db-client-sg"
  description = "Designated security group for resources allowed to access MySQL."
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow outbound traffic to MySQL database"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "mysql-db-client-sg"
  }
}

resource "aws_security_group" "db" {
  name        = "mysql-db-sg"
  description = "Security group for MySQL RDS instance."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow MySQL access from designated client security group"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.db_client.id]
  }

  egress {
    description = "Allow all outbound traffic from database"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mysql-db-sg"
  }
}

resource "aws_db_subnet_group" "mysql" {
  name        = "mysql-public-db-subnet-group"
  description = "Subnet group for MySQL RDS instance in public subnets."
  subnet_ids = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]

  tags = {
    Name = "mysql-public-db-subnet-group"
  }
}

resource "aws_db_instance" "mysql" {
  identifier = "mysql-843-instance"

  engine         = "mysql"
  engine_version = "8.4.3"

  instance_class        = var.db_instance_class
  allocated_storage     = 20
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  port = 3306

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.db.id]

  publicly_accessible = true
  multi_az             = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  deletion_protection = false
  skip_final_snapshot = true

  auto_minor_version_upgrade = false
  copy_tags_to_snapshot      = true

  tags = {
    Name = "mysql-843-instance"
  }
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]
}

output "database_security_group_id" {
  description = "Security group ID attached to the MySQL database."
  value       = aws_security_group.db.id
}

output "database_client_security_group_id" {
  description = "Designated client security group ID allowed to access MySQL."
  value       = aws_security_group.db_client.id
}

output "mysql_endpoint" {
  description = "MySQL RDS endpoint."
  value       = aws_db_instance.mysql.endpoint
}

output "mysql_port" {
  description = "MySQL RDS port."
  value       = aws_db_instance.mysql.port
}

output "mysql_database_name" {
  description = "Initial MySQL database name."
  value       = aws_db_instance.mysql.db_name
}

output "mysql_username" {
  description = "MySQL master username."
  value       = var.db_username
}

output "mysql_password" {
  description = "Generated MySQL master password."
  value       = random_password.db_password.result
  sensitive   = true
}