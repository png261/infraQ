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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_1_cidr_block" {
  description = "CIDR block for the first subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_2_cidr_block" {
  description = "CIDR block for the second subnet."
  type        = string
  default     = "10.0.2.0/24"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "database_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "database-vpc"
  }
}

resource "aws_internet_gateway" "database_igw" {
  vpc_id = aws_vpc.database_vpc.id

  tags = {
    Name = "database-internet-gateway"
  }
}

resource "aws_subnet" "database_subnet_1" {
  vpc_id                  = aws_vpc.database_vpc.id
  cidr_block              = var.subnet_1_cidr_block
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "database-subnet-1"
  }
}

resource "aws_subnet" "database_subnet_2" {
  vpc_id                  = aws_vpc.database_vpc.id
  cidr_block              = var.subnet_2_cidr_block
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "database-subnet-2"
  }
}

resource "aws_route_table" "database_public_route_table" {
  vpc_id = aws_vpc.database_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.database_igw.id
  }

  tags = {
    Name = "database-public-route-table"
  }
}

resource "aws_route_table_association" "database_subnet_1_association" {
  subnet_id      = aws_subnet.database_subnet_1.id
  route_table_id = aws_route_table.database_public_route_table.id
}

resource "aws_route_table_association" "database_subnet_2_association" {
  subnet_id      = aws_subnet.database_subnet_2.id
  route_table_id = aws_route_table.database_public_route_table.id
}

resource "aws_security_group" "database_access_sg" {
  name        = "database-access-security-group"
  description = "Allow inbound MySQL and PostgreSQL access from any IPv4 address"
  vpc_id      = aws_vpc.database_vpc.id

  ingress {
    description = "Allow MySQL access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow PostgreSQL access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound IPv4 traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "database-access-security-group"
  }
}

resource "aws_db_subnet_group" "database_subnet_group" {
  name        = "database-subnet-group"
  description = "Database subnet group spanning two availability zones"
  subnet_ids = [
    aws_subnet.database_subnet_1.id,
    aws_subnet.database_subnet_2.id
  ]

  tags = {
    Name = "database-subnet-group"
  }
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.database_vpc.id
}

output "subnet_ids" {
  description = "IDs of the created subnets."
  value = [
    aws_subnet.database_subnet_1.id,
    aws_subnet.database_subnet_2.id
  ]
}

output "security_group_id" {
  description = "ID of the database access security group."
  value       = aws_security_group.database_access_sg.id
}

output "db_subnet_group_name" {
  description = "Name of the database subnet group."
  value       = aws_db_subnet_group.database_subnet_group.name
}