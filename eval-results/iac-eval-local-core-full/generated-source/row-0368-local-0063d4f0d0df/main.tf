terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_lightsail_database" "mysql" {
  relational_database_name = "benchmark-mysql-database"
  master_database_name     = "benchmarkdb"
  master_username          = "benchmarkadmin"
  master_password          = var.master_password
  blueprint_id             = "mysql_8_0"
  bundle_id                = "micro_2_0"

  preferred_backup_window      = "16:00-16:30"
  preferred_maintenance_window = "Tue:17:00-Tue:17:30"
}
