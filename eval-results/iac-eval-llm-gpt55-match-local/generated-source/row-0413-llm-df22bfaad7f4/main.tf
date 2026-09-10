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
  description = "AWS region where the RDS resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "db_username" {
  description = "Master username for the source RDS database."
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "Master password for the source RDS database."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}

variable "db_instance_class" {
  description = "Instance class for both source and restored RDS databases."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB for the source RDS database."
  type        = number
  default     = 20
}

locals {
  name_prefix = "snapshot-restore-demo"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.40.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${local.name_prefix}-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.40.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${local.name_prefix}-private-b"
  }
}

resource "aws_db_subnet_group" "main" {
  name = "${local.name_prefix}-subnet-group"

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = {
    Name = "${local.name_prefix}-subnet-group"
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Security group for RDS databases"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow PostgreSQL from within the VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [
      aws_vpc.main.cidr_block
    ]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags = {
    Name = "${local.name_prefix}-rds-sg"
  }
}

resource "aws_db_instance" "source" {
  identifier = "${local.name_prefix}-source-db"

  engine         = "postgres"
  engine_version = "16.3"
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"

  db_name  = "sourcedb"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false

  apply_immediately = true

  tags = {
    Name = "${local.name_prefix}-source-db"
  }
}

resource "aws_db_snapshot" "source_snapshot" {
  db_instance_identifier = aws_db_instance.source.identifier
  db_snapshot_identifier = "${local.name_prefix}-source-snapshot"

  tags = {
    Name = "${local.name_prefix}-source-snapshot"
  }
}

resource "aws_db_instance" "restored" {
  identifier = "${local.name_prefix}-restored-db"

  snapshot_identifier = aws_db_snapshot.source_snapshot.id
  instance_class      = var.db_instance_class

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  multi_az            = false

  skip_final_snapshot = true
  deletion_protection = false

  apply_immediately = true

  tags = {
    Name = "${local.name_prefix}-restored-db"
  }
}

output "source_db_endpoint" {
  description = "Endpoint of the original source RDS database."
  value       = aws_db_instance.source.endpoint
}

output "snapshot_identifier" {
  description = "Identifier of the RDS snapshot used for restore."
  value       = aws_db_snapshot.source_snapshot.id
}

output "restored_db_endpoint" {
  description = "Endpoint of the RDS database restored from the snapshot."
  value       = aws_db_instance.restored.endpoint
}