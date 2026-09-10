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
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "basicdb"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the RDS instance"
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}

variable "allowed_cidr" {
  description = "CIDR block allowed to connect to MySQL"
  type        = string
  default     = "0.0.0.0/0"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "rds_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "basic-rds-vpc"
  }
}

resource "aws_internet_gateway" "rds_igw" {
  vpc_id = aws_vpc.rds_vpc.id

  tags = {
    Name = "basic-rds-igw"
  }
}

resource "aws_subnet" "rds_subnet_1" {
  vpc_id                  = aws_vpc.rds_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "basic-rds-subnet-1"
  }
}

resource "aws_subnet" "rds_subnet_2" {
  vpc_id                  = aws_vpc.rds_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "basic-rds-subnet-2"
  }
}

resource "aws_route_table" "rds_public_rt" {
  vpc_id = aws_vpc.rds_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.rds_igw.id
  }

  tags = {
    Name = "basic-rds-public-rt"
  }
}

resource "aws_route_table_association" "rds_subnet_1_assoc" {
  subnet_id      = aws_subnet.rds_subnet_1.id
  route_table_id = aws_route_table.rds_public_rt.id
}

resource "aws_route_table_association" "rds_subnet_2_assoc" {
  subnet_id      = aws_subnet.rds_subnet_2.id
  route_table_id = aws_route_table.rds_public_rt.id
}

resource "aws_security_group" "rds_sg" {
  name        = "basic-rds-sg"
  description = "Allow MySQL access to RDS"
  vpc_id      = aws_vpc.rds_vpc.id

  ingress {
    description = "MySQL access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "basic-rds-sg"
  }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "basic-rds-subnet-group"
  subnet_ids = [
    aws_subnet.rds_subnet_1.id,
    aws_subnet.rds_subnet_2.id
  ]

  tags = {
    Name = "basic-rds-subnet-group"
  }
}

resource "aws_db_instance" "basic_rds" {
  identifier             = "basic-rds-instance"
  db_name                = var.db_name
  allocated_storage      = 20
  max_allocated_storage  = 100
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  username               = var.db_username
  password               = var.db_password
  port                   = 3306

  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  publicly_accessible    = true
  multi_az               = false
  skip_final_snapshot    = true
  deletion_protection    = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  tags = {
    Name = "basic-rds-instance"
  }
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.basic_rds.endpoint
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.basic_rds.port
}

output "database_name" {
  description = "Initial database name"
  value       = aws_db_instance.basic_rds.db_name
}