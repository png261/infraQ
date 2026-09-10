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

resource "aws_db_instance" "basic" {
  identifier        = "basic-gp3-rds-instance"
  allocated_storage = 20
  storage_type      = "gp3"
  engine            = "mysql"
  instance_class    = "db.t3.micro"
  username          = "admin"
  password          = "ChangeMe123!"

  skip_final_snapshot = true
}
