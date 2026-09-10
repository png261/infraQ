terraform {
  required_version = ">= 1.3.0"

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

variable "db_username" {
  description = "Master username for the MySQL RDS instance."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the MySQL RDS instance."
  type        = string
  sensitive   = true
  default     = "ChangeMe123456!"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
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

resource "aws_subnet" "subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "main-rds-subnet-a"
  }
}

resource "aws_subnet" "subnet_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "main-rds-subnet-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-rds-public-route-table"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "subnet_a_public" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "subnet_b_public" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "mysql_access" {
  name        = "mysql-rds-access-sg"
  description = "Allow MySQL database access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow MySQL access from anywhere"
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
    Name = "mysql-rds-access-sg"
  }
}

resource "aws_db_subnet_group" "mysql" {
  name        = "mysql-rds-subnet-group"
  description = "Subnet group for publicly accessible MySQL RDS instance"

  subnet_ids = [
    aws_subnet.subnet_a.id,
    aws_subnet.subnet_b.id
  ]

  tags = {
    Name = "mysql-rds-subnet-group"
  }
}

resource "aws_db_instance" "mysql" {
  identifier = "public-mysql-57-db"

  engine         = "mysql"
  engine_version = "5.7"

  instance_class    = "db.t3.micro"
  allocated_storage = 10
  storage_type      = "gp2"

  db_name  = "appdb"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.mysql_access.id]

  publicly_accessible = true
  port                = 3306

  multi_az               = false
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false

  auto_minor_version_upgrade = false

  tags = {
    Name = "public-mysql-57-db"
  }
}

output "database_endpoint" {
  description = "The connection endpoint for the MySQL RDS database."
  value       = aws_db_instance.mysql.endpoint
}

output "database_port" {
  description = "The MySQL database port."
  value       = aws_db_instance.mysql.port
}