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
  description = "AWS region where the Aurora PostgreSQL cluster will be created."
  type        = string
  default     = "us-east-1"
}

variable "cluster_identifier" {
  description = "Identifier for the Aurora PostgreSQL cluster."
  type        = string
  default     = "example-aurora-postgresql-cluster"
}

variable "database_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Master username for the Aurora PostgreSQL cluster."
  type        = string
  default     = "dbadmin"
}

variable "instance_class" {
  description = "Instance class for Aurora PostgreSQL instances."
  type        = string
  default     = "db.r6g.large"
}

variable "instance_count" {
  description = "Number of Aurora PostgreSQL instances to create."
  type        = number
  default     = 2
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups."
  type        = number
  default     = 7
}

variable "preferred_backup_window" {
  description = "Preferred backup window."
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Preferred maintenance window."
  type        = string
  default     = "sun:04:00-sun:05:00"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "random_password" "master_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_security_group" "aurora_postgresql" {
  name        = "${var.cluster_identifier}-sg"
  description = "Security group for Aurora PostgreSQL cluster"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow PostgreSQL access from within the default VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_identifier}-sg"
  }
}

resource "aws_db_subnet_group" "aurora_postgresql" {
  name        = "${var.cluster_identifier}-subnet-group"
  description = "Subnet group for Aurora PostgreSQL cluster"
  subnet_ids  = data.aws_subnets.default.ids

  tags = {
    Name = "${var.cluster_identifier}-subnet-group"
  }
}

resource "aws_rds_cluster_parameter_group" "aurora_postgresql" {
  name        = "${var.cluster_identifier}-cluster-pg"
  family      = "aurora-postgresql15"
  description = "Cluster parameter group for Aurora PostgreSQL"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = {
    Name = "${var.cluster_identifier}-cluster-pg"
  }
}

resource "aws_db_parameter_group" "aurora_postgresql" {
  name        = "${var.cluster_identifier}-instance-pg"
  family      = "aurora-postgresql15"
  description = "Instance parameter group for Aurora PostgreSQL"

  tags = {
    Name = "${var.cluster_identifier}-instance-pg"
  }
}

resource "aws_rds_cluster" "aurora_postgresql" {
  cluster_identifier              = var.cluster_identifier
  engine                          = "aurora-postgresql"
  engine_version                  = "15.4"
  database_name                   = var.database_name
  master_username                 = var.master_username
  master_password                 = random_password.master_password.result
  port                            = 5432
  db_subnet_group_name            = aws_db_subnet_group.aurora_postgresql.name
  vpc_security_group_ids          = [aws_security_group.aurora_postgresql.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora_postgresql.name

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  storage_encrypted = true

  deletion_protection = false
  skip_final_snapshot = true

  apply_immediately = true

  tags = {
    Name = var.cluster_identifier
  }
}

resource "aws_rds_cluster_instance" "aurora_postgresql" {
  count = var.instance_count

  identifier              = "${var.cluster_identifier}-${count.index + 1}"
  cluster_identifier      = aws_rds_cluster.aurora_postgresql.id
  instance_class          = var.instance_class
  engine                  = aws_rds_cluster.aurora_postgresql.engine
  engine_version          = aws_rds_cluster.aurora_postgresql.engine_version
  db_subnet_group_name    = aws_db_subnet_group.aurora_postgresql.name
  db_parameter_group_name = aws_db_parameter_group.aurora_postgresql.name

  publicly_accessible = false
  apply_immediately   = true

  tags = {
    Name = "${var.cluster_identifier}-${count.index + 1}"
  }
}

output "aurora_cluster_identifier" {
  description = "Aurora PostgreSQL cluster identifier."
  value       = aws_rds_cluster.aurora_postgresql.cluster_identifier
}

output "aurora_cluster_endpoint" {
  description = "Writer endpoint for the Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.aurora_postgresql.endpoint
}

output "aurora_reader_endpoint" {
  description = "Reader endpoint for the Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.aurora_postgresql.reader_endpoint
}

output "aurora_database_name" {
  description = "Initial database name."
  value       = aws_rds_cluster.aurora_postgresql.database_name
}

output "aurora_master_username" {
  description = "Master username for the Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.aurora_postgresql.master_username
}

output "aurora_master_password" {
  description = "Generated master password for the Aurora PostgreSQL cluster."
  value       = random_password.master_password.result
  sensitive   = true
}