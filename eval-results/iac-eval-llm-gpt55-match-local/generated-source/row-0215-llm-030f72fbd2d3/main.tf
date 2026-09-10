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

variable "vpc_cidr" {
  description = "CIDR block for the Aurora VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
}

variable "db_master_username" {
  description = "Aurora MySQL master username."
  type        = string
  default     = "adminuser"
}

variable "db_master_password" {
  description = "Aurora MySQL master password."
  type        = string
  sensitive   = true
  default     = "ChangeMe123456789!"
}

variable "allowed_mysql_cidr" {
  description = "CIDR block allowed to connect to Aurora MySQL."
  type        = string
  default     = "0.0.0.0/0"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "aurora_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "aurora-mysql-vpc"
  }
}

resource "aws_internet_gateway" "aurora_igw" {
  vpc_id = aws_vpc.aurora_vpc.id

  tags = {
    Name = "aurora-mysql-igw"
  }
}

resource "aws_subnet" "aurora_subnet_a" {
  vpc_id                  = aws_vpc.aurora_vpc.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "aurora-mysql-subnet-a"
  }
}

resource "aws_subnet" "aurora_subnet_b" {
  vpc_id                  = aws_vpc.aurora_vpc.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "aurora-mysql-subnet-b"
  }
}

resource "aws_route_table" "aurora_public_rt" {
  vpc_id = aws_vpc.aurora_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.aurora_igw.id
  }

  tags = {
    Name = "aurora-mysql-public-rt"
  }
}

resource "aws_route_table_association" "aurora_subnet_a_assoc" {
  subnet_id      = aws_subnet.aurora_subnet_a.id
  route_table_id = aws_route_table.aurora_public_rt.id
}

resource "aws_route_table_association" "aurora_subnet_b_assoc" {
  subnet_id      = aws_subnet.aurora_subnet_b.id
  route_table_id = aws_route_table.aurora_public_rt.id
}

resource "aws_security_group" "aurora_sg" {
  name        = "aurora-mysql-sg"
  description = "Security group for Aurora MySQL cluster"
  vpc_id      = aws_vpc.aurora_vpc.id

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
    Name = "aurora-mysql-sg"
  }
}

resource "aws_db_subnet_group" "aurora_subnet_group" {
  name        = "aurora-mysql-subnet-group"
  description = "Subnet group for Aurora MySQL"
  subnet_ids = [
    aws_subnet.aurora_subnet_a.id,
    aws_subnet.aurora_subnet_b.id
  ]

  tags = {
    Name = "aurora-mysql-subnet-group"
  }
}

resource "aws_rds_cluster_parameter_group" "aurora_mysql_cluster_pg" {
  name        = "aurora-mysql-cluster-parameter-group"
  family      = "aurora-mysql8.0"
  description = "Aurora MySQL 8.0 cluster parameter group"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = {
    Name = "aurora-mysql-cluster-parameter-group"
  }
}

resource "aws_db_parameter_group" "aurora_mysql_instance_pg" {
  name        = "aurora-mysql-instance-parameter-group"
  family      = "aurora-mysql8.0"
  description = "Aurora MySQL 8.0 instance parameter group"

  tags = {
    Name = "aurora-mysql-instance-parameter-group"
  }
}

resource "aws_rds_cluster" "aurora_mysql" {
  cluster_identifier              = "aurora-mysql-cluster"
  engine                          = "aurora-mysql"
  engine_version                  = "8.0.mysql_aurora.3.05.2"
  database_name                   = var.db_name
  master_username                 = var.db_master_username
  master_password                 = var.db_master_password
  db_subnet_group_name            = aws_db_subnet_group.aurora_subnet_group.name
  vpc_security_group_ids          = [aws_security_group.aurora_sg.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora_mysql_cluster_pg.name
  backup_retention_period         = 7
  preferred_backup_window         = "03:00-04:00"
  preferred_maintenance_window    = "sun:04:00-sun:05:00"
  storage_encrypted               = true
  skip_final_snapshot             = true
  deletion_protection             = false

  tags = {
    Name = "aurora-mysql-cluster"
  }
}

resource "aws_rds_cluster_instance" "aurora_mysql_instance_1" {
  identifier                 = "aurora-mysql-instance-1"
  cluster_identifier         = aws_rds_cluster.aurora_mysql.id
  instance_class             = "db.r6g.large"
  engine                     = aws_rds_cluster.aurora_mysql.engine
  engine_version             = aws_rds_cluster.aurora_mysql.engine_version
  db_subnet_group_name       = aws_db_subnet_group.aurora_subnet_group.name
  db_parameter_group_name    = aws_db_parameter_group.aurora_mysql_instance_pg.name
  publicly_accessible        = true
  auto_minor_version_upgrade = true

  tags = {
    Name = "aurora-mysql-instance-1"
  }
}

resource "aws_rds_cluster_instance" "aurora_mysql_instance_2" {
  identifier                 = "aurora-mysql-instance-2"
  cluster_identifier         = aws_rds_cluster.aurora_mysql.id
  instance_class             = "db.r6g.large"
  engine                     = aws_rds_cluster.aurora_mysql.engine
  engine_version             = aws_rds_cluster.aurora_mysql.engine_version
  db_subnet_group_name       = aws_db_subnet_group.aurora_subnet_group.name
  db_parameter_group_name    = aws_db_parameter_group.aurora_mysql_instance_pg.name
  publicly_accessible        = true
  auto_minor_version_upgrade = true

  tags = {
    Name = "aurora-mysql-instance-2"
  }
}

output "aurora_cluster_endpoint" {
  description = "Aurora MySQL writer endpoint."
  value       = aws_rds_cluster.aurora_mysql.endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora MySQL reader endpoint."
  value       = aws_rds_cluster.aurora_mysql.reader_endpoint
}

output "aurora_cluster_port" {
  description = "Aurora MySQL port."
  value       = aws_rds_cluster.aurora_mysql.port
}

output "aurora_database_name" {
  description = "Initial Aurora MySQL database name."
  value       = aws_rds_cluster.aurora_mysql.database_name
}