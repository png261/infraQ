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

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "aurora-postgresql-vpc"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidr_blocks)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr_blocks[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "aurora-postgresql-private-${count.index + 1}"
  }
}

resource "aws_db_subnet_group" "aurora" {
  name       = "aurora-postgresql-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "aurora-postgresql-subnet-group"
  }
}

resource "aws_security_group" "aurora" {
  name        = "aurora-postgresql-sg"
  description = "Security group for Aurora PostgreSQL cluster"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "aurora-postgresql-sg"
  }
}

resource "aws_rds_cluster" "aurora_postgresql" {
  cluster_identifier     = var.cluster_identifier
  engine                 = "aurora-postgresql"
  engine_version         = var.engine_version
  database_name          = var.database_name
  master_username        = var.master_username
  master_password        = var.master_password
  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id]
  skip_final_snapshot    = true

  tags = {
    Name = var.cluster_identifier
  }
}

resource "aws_rds_cluster_instance" "aurora_postgresql" {
  identifier         = "${var.cluster_identifier}-instance-1"
  cluster_identifier = aws_rds_cluster.aurora_postgresql.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.aurora_postgresql.engine
  engine_version     = aws_rds_cluster.aurora_postgresql.engine_version

  tags = {
    Name = "${var.cluster_identifier}-instance-1"
  }
}
