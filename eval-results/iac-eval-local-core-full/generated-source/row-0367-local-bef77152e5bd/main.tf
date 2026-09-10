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

resource "aws_lightsail_database" "mysql" {
  relational_database_name = var.relational_database_name
  availability_zone        = var.availability_zone
  master_database_name     = var.master_database_name
  master_username          = var.master_username
  master_password          = var.master_password
  blueprint_id             = "mysql_8_0"
  bundle_id                = var.bundle_id
}
