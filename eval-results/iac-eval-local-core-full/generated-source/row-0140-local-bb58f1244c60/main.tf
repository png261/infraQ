terraform {
  required_version = ">= 1.6.0"

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

resource "aws_redshift_cluster" "benchmark" {
  cluster_identifier  = "iac-eval-redshift-cluster"
  database_name       = "benchmarkdb"
  master_username     = "benchmarkadmin"
  master_password     = var.redshift_master_password
  node_type           = "dc2.large"
  cluster_type        = "multi-node"
  number_of_nodes     = 2
  skip_final_snapshot = true
}

resource "aws_redshift_usage_limit" "concurrency_scaling" {
  cluster_identifier = aws_redshift_cluster.benchmark.cluster_identifier
  feature_type       = "concurrency-scaling"
  limit_type         = "time"
  amount             = 60
}
