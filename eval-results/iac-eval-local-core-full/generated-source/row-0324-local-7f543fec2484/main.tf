terraform {
  required_version = ">= 1.6.0"

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

resource "random_id" "rds_identifier" {
  byte_length = 4
  prefix      = "benchmark-rds-"
}

resource "random_password" "rds_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_db_instance" "benchmark" {
  identifier          = random_id.rds_identifier.hex
  allocated_storage   = 20
  engine              = "mysql"
  instance_class      = "db.t3.micro"
  username            = "benchmark_admin"
  password            = random_password.rds_password.result
  skip_final_snapshot = true
}
