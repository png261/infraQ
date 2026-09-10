terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "iac-eval-mysql-cluster-vpc"
  }
}

resource "aws_subnet" "database" {
  for_each = {
    us_east_1a = {
      cidr_block        = "10.0.1.0/24"
      availability_zone = "us-east-1a"
    }
    us_east_1b = {
      cidr_block        = "10.0.2.0/24"
      availability_zone = "us-east-1b"
    }
    us_east_1c = {
      cidr_block        = "10.0.3.0/24"
      availability_zone = "us-east-1c"
    }
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  tags = {
    Name = "iac-eval-mysql-cluster-${each.value.availability_zone}"
  }
}

resource "aws_db_subnet_group" "database" {
  name       = "iac-eval-mysql-cluster-subnets"
  subnet_ids = [for subnet in aws_subnet.database : subnet.id]

  tags = {
    Name = "iac-eval-mysql-cluster-subnets"
  }
}

resource "aws_security_group" "database" {
  name        = "iac-eval-mysql-cluster-sg"
  description = "Security group for the benchmark MySQL RDS cluster"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iac-eval-mysql-cluster-sg"
  }
}

resource "aws_rds_cluster" "mysql" {
  cluster_identifier           = "iac-eval-mysql-cluster"
  engine                       = "mysql"
  engine_version               = "8.0.35"
  engine_mode                  = "provisioned"
  db_cluster_instance_class    = "db.r6gd.xlarge"
  allocated_storage            = 100
  storage_type                 = "io1"
  iops                         = 1000
  master_username              = var.db_master_username
  master_password              = var.db_master_password
  db_subnet_group_name         = aws_db_subnet_group.database.name
  vpc_security_group_ids       = [aws_security_group.database.id]
  skip_final_snapshot          = true
  deletion_protection          = false
  apply_immediately            = true
  backup_retention_period      = 1
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  tags = {
    Name = "iac-eval-mysql-cluster"
  }
}
