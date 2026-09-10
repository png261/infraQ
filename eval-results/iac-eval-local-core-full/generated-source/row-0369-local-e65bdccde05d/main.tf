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

resource "aws_lightsail_database" "postgres" {
  relational_database_name = "benchmark-postgres-db"
  master_database_name     = "benchmarkdb"
  master_username          = "benchmarkadmin"
  master_password          = var.master_password
  blueprint_id             = "postgres_12"
  bundle_id                = "micro_2_0"
  final_snapshot_name      = "benchmark-postgres-db-final-snapshot"
}
