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

resource "aws_db_instance" "mysql" {
  allocated_storage   = 20
  engine              = "mysql"
  instance_class      = "db.t3.micro"
  username            = var.db_username
  password            = var.db_password
  skip_final_snapshot = true
}

resource "aws_db_snapshot" "mysql" {
  db_instance_identifier = aws_db_instance.mysql.identifier
  db_snapshot_identifier = "benchmark-mysql-snapshot"
}
