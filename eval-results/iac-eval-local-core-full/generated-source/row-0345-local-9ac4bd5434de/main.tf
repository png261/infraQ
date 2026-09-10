terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "random_string" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_security_group" "mysql_public" {
  name        = "iac-eval-mysql-public"
  description = "Public MySQL access for IaC evaluation benchmark"

  ingress {
    description = "Allow public MySQL access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "mysql" {
  identifier             = "iac-eval-mysql"
  allocated_storage      = 20
  engine                 = "mysql"
  instance_class         = "db.t3.micro"
  db_name                = "iaceval"
  username               = "adminuser"
  password               = random_string.db_password.result
  publicly_accessible    = true
  vpc_security_group_ids = [aws_security_group.mysql_public.id]
  skip_final_snapshot    = false
  final_snapshot_identifier = "iac-eval-mysql-final-snapshot"
}
