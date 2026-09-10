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
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "allowed_db_cidr" {
  description = "CIDR block allowed to access PostgreSQL. Restrict this in production."
  type        = string
  default     = "0.0.0.0/0"
}

variable "db_username" {
  description = "Master username for PostgreSQL."
  type        = string
  default     = "dolphinadmin"
}

variable "db_password" {
  description = "Master password for PostgreSQL."
  type        = string
  sensitive   = true
  default     = "DolphinScheduler123!"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "dolphinscheduler-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "dolphinscheduler-igw"
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "dolphinscheduler-public-subnet-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "dolphinscheduler-public-rt"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "postgres" {
  name        = "dolphinscheduler-postgres-sg"
  description = "Security group for PostgreSQL database access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow PostgreSQL access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.allowed_db_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "dolphinscheduler-postgres-sg"
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "dolphinscheduler-db-subnet-group"
  subnet_ids = aws_subnet.public[*].id

  tags = {
    Name = "dolphinscheduler-db-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "dolphinscheduler"

  engine         = "postgres"
  engine_version = "17.1"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 20
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "dolphinscheduler"
  username = var.db_username
  password = var.db_password

  port = 5432

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]

  publicly_accessible = true
  multi_az            = false

  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  auto_minor_version_upgrade = false
  apply_immediately          = true

  tags = {
    Name = "dolphinscheduler"
  }
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "postgres_security_group_id" {
  description = "Security group ID for PostgreSQL access."
  value       = aws_security_group.postgres.id
}

output "postgres_endpoint" {
  description = "PostgreSQL RDS endpoint."
  value       = aws_db_instance.postgres.endpoint
}

output "postgres_port" {
  description = "PostgreSQL port."
  value       = aws_db_instance.postgres.port
}