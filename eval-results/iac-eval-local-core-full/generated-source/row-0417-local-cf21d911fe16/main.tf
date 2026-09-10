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

resource "aws_db_instance" "benchmark" {
  identifier            = "iac-eval-storage-autoscaling-db"
  allocated_storage     = 20
  max_allocated_storage = 100
  engine                = "mysql"
  instance_class        = "db.t3.micro"
  username              = "adminuser"
  password              = "ChangeMe123!"
  db_name               = "benchmark"
  skip_final_snapshot   = true
}
