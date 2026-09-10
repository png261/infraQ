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

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the PostgreSQL database."
  type        = string
  default     = "dbadmin"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for the database in GB."
  type        = number
  default     = 20
}

variable "allowed_db_cidr_blocks" {
  description = "Optional CIDR blocks allowed to connect directly to PostgreSQL on port 5432. Leave empty to allow only the database client security group."
  type        = list(string)
  default     = []
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
    Name = "postgres-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "postgres-vpc-igw"
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "postgres-public-subnet-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "postgres-public-route-table"
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

resource "aws_security_group" "db_client" {
  name        = "postgres-db-client-sg"
  description = "Security group for resources allowed to access PostgreSQL."
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow outbound traffic to PostgreSQL and other services."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "postgres-db-client-sg"
  }
}

resource "aws_security_group" "database" {
  name        = "postgres-database-sg"
  description = "Security group controlling access to the PostgreSQL database."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow PostgreSQL access from the designated database client security group."
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.db_client.id]
  }

  dynamic "ingress" {
    for_each = var.allowed_db_cidr_blocks

    content {
      description = "Allow PostgreSQL access from configured CIDR block."
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "Allow all outbound traffic from the database."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "postgres-database-sg"
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "postgres-public-db-subnet-group"
  subnet_ids = aws_subnet.public[*].id

  tags = {
    Name = "postgres-public-db-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "postgres-vpc-db"

  engine         = "postgres"
  engine_version = "16.3"

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.database.id]

  publicly_accessible = true
  multi_az            = false

  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = {
    Name = "postgres-vpc-db"
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

output "database_security_group_id" {
  description = "Security group ID attached to the PostgreSQL database."
  value       = aws_security_group.database.id
}

output "database_client_security_group_id" {
  description = "Security group ID that is allowed to access PostgreSQL."
  value       = aws_security_group.db_client.id
}

output "postgres_endpoint" {
  description = "PostgreSQL RDS endpoint."
  value       = aws_db_instance.postgres.endpoint
}

output "postgres_port" {
  description = "PostgreSQL port."
  value       = aws_db_instance.postgres.port
}

output "postgres_database_name" {
  description = "Initial PostgreSQL database name."
  value       = aws_db_instance.postgres.db_name
}

output "postgres_username" {
  description = "PostgreSQL master username."
  value       = var.db_username
}

output "postgres_password" {
  description = "Generated PostgreSQL master password."
  value       = random_password.db_password.result
  sensitive   = true
}