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
  name = "iac-eval-postgres"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = local.name
  }
}

resource "aws_subnet" "database" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, 1)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${local.name}-db"
  }
}

resource "aws_db_subnet_group" "database" {
  name       = "${local.name}-subnet-group"
  subnet_ids = [aws_subnet.database.id]

  tags = {
    Name = "${local.name}-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = local.name

  allocated_storage     = 5
  max_allocated_storage = 50
  engine                = "postgres"
  engine_version        = "16.3"
  instance_class        = "db.t3.micro"

  db_name  = "appdb"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name = aws_db_subnet_group.database.name
  publicly_accessible  = false
  skip_final_snapshot   = true

  maintenance_window = "Mon:00:00-Mon:03:00"
}
