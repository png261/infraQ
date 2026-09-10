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

resource "aws_redshift_cluster" "this" {
  cluster_identifier = "benchmark-redshift-cluster"
  database_name      = "benchmarkdb"
  master_username    = "benchmark_admin"
  master_password    = var.redshift_master_password
  node_type          = "dc2.large"
  cluster_type       = "single-node"

  skip_final_snapshot = true
}

resource "aws_redshift_snapshot_schedule" "every_12_hours" {
  identifier  = "benchmark-redshift-every-12-hours"
  definitions = ["rate(12 hours)"]
}

resource "aws_redshift_snapshot_schedule_association" "this" {
  cluster_identifier  = aws_redshift_cluster.this.cluster_identifier
  schedule_identifier = aws_redshift_snapshot_schedule.every_12_hours.identifier
}
