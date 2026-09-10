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

resource "aws_db_instance" "from_snapshot" {
  identifier          = "benchmark-db-from-snapshot"
  allocated_storage   = 20
  engine              = "mysql"
  instance_class      = "db.t3.micro"
  username            = var.db_username
  password            = var.db_password
  snapshot_identifier = var.snapshot_identifier
  skip_final_snapshot = true
}
