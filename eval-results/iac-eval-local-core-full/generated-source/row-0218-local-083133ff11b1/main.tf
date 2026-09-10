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
  region = "us-east-1"
}

locals {
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "iac-eval-rds-vpc"
  }
}

resource "aws_subnet" "rds" {
  for_each = {
    for index, az in local.availability_zones : az => cidrsubnet(aws_vpc.main.cidr_block, 8, index)
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = {
    Name = "iac-eval-rds-${each.key}"
  }
}

resource "aws_security_group" "rds" {
  name        = "iac-eval-rds-mysql"
  description = "Security group for the benchmark MySQL RDS cluster"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iac-eval-rds-mysql"
  }
}

resource "aws_db_subnet_group" "rds" {
  name       = "iac-eval-rds-subnets"
  subnet_ids = [for subnet in aws_subnet.rds : subnet.id]

  tags = {
    Name = "iac-eval-rds-subnets"
  }
}

resource "aws_rds_cluster" "mysql" {
  cluster_identifier        = "iac-eval-mysql-cluster"
  engine                    = "mysql"
  allocated_storage         = 100
  availability_zones        = ["us-east-1a", "us-east-1b", "us-east-1c"]
  db_cluster_instance_class = var.db_cluster_instance_class
  db_subnet_group_name      = aws_db_subnet_group.rds.name
  master_username           = var.master_username
  master_password           = var.master_password
  skip_final_snapshot       = true
  vpc_security_group_ids    = [aws_security_group.rds.id]

  tags = {
    Name = "iac-eval-mysql-cluster"
  }
}
