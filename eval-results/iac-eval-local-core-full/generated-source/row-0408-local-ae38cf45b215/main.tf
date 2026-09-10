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

resource "aws_db_instance" "postgres" {
  allocated_storage   = 20
  engine              = "postgres"
  instance_class      = "db.t4g.large"
  username            = var.db_username
  password            = var.db_password
  skip_final_snapshot = true
}
