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
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "iac-eval-mysql-vpc"
  }
}

resource "aws_subnet" "db" {
  for_each = {
    a = {
      cidr_block        = "10.0.1.0/24"
      availability_zone = "us-east-1a"
    }
    b = {
      cidr_block        = "10.0.2.0/24"
      availability_zone = "us-east-1b"
    }
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  tags = {
    Name = "iac-eval-mysql-db-${each.key}"
  }
}

resource "aws_security_group" "mysql" {
  name        = "iac-eval-mysql-sg"
  description = "Security group for private MySQL benchmark instance"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iac-eval-mysql-sg"
  }
}

resource "aws_db_subnet_group" "mysql" {
  name       = "iac-eval-mysql-subnet-group"
  subnet_ids = [for subnet in aws_subnet.db : subnet.id]

  tags = {
    Name = "iac-eval-mysql-subnet-group"
  }
}

resource "aws_db_instance" "mysql" {
  identifier             = "iac-eval-mysql"
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "iac_eval"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.mysql.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false

  tags = {
    Name = "iac-eval-mysql"
  }
}
