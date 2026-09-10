terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the main VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_1_cidr" {
  description = "CIDR block for the first public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_2_cidr" {
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
  description = "Master username for the MySQL RDS instance."
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "Master password for the MySQL RDS instance."
  type        = string
  sensitive   = true
  default     = "ChangeMe123!"
}

variable "allowed_mysql_cidr" {
  description = "CIDR block allowed to connect to MySQL. Replace with your trusted IP range for production."
  type        = string
  default     = "0.0.0.0/0"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-rds-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-rds-igw"
  }
}

resource "aws_subnet" "subnet_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_1_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "main-rds-public-subnet-1"
  }
}

resource "aws_subnet" "subnet_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_2_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "main-rds-public-subnet-2"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-rds-public-route-table"
  }
}

resource "aws_route" "default_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "subnet_1_public" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "subnet_2_public" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "mysql" {
  name        = "mysql-rds-access-sg"
  description = "Allow MySQL database access"
  vpc_id      = aws_vpc.main.id

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
    Name = "mysql-rds-access-sg"
  }
}

resource "aws_db_subnet_group" "mysql" {
  name        = "mysql-rds-subnet-group"
  description = "Subnet group for public MySQL RDS instance"

  subnet_ids = [
    aws_subnet.subnet_1.id,
    aws_subnet.subnet_2.id
  ]

  tags = {
    Name = "mysql-rds-subnet-group"
  }
}

resource "aws_db_instance" "mysql" {
  identifier = "public-mysql-57-rds"

  engine         = "mysql"
  engine_version = "5.7"

  instance_class    = "db.t3.medium"
  allocated_storage = 500
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  port = 3306

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.mysql.id]

  publicly_accessible = true
  multi_az            = false

  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  apply_immediately = true

  auto_minor_version_upgrade = false

  tags = {
    Name = "public-mysql-57-rds"
  }
}

output "database_endpoint" {
  description = "The connection endpoint for the MySQL RDS instance."
  value       = aws_db_instance.mysql.endpoint
}

output "database_port" {
  description = "The MySQL database port."
  value       = aws_db_instance.mysql.port
}

output "database_name" {
  description = "The initial MySQL database name."
  value       = aws_db_instance.mysql.db_name
}