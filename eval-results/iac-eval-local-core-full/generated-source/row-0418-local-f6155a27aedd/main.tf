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

resource "aws_db_instance" "managed_master_password" {
  allocated_storage = 20
  engine            = "postgres"
  instance_class    = "db.t3.micro"
  username          = "dbadmin"

  manage_master_user_password = true

  skip_final_snapshot = true
}
