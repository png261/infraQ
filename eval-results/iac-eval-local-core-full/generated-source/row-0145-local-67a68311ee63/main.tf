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

provider "aws" {
  alias  = "replica"
  region = "us-east-2"
}

resource "aws_redshift_cluster" "primary" {
  cluster_identifier = var.cluster_identifier
  database_name      = var.database_name
  master_username    = var.master_username
  master_password    = var.master_password

  node_type       = var.node_type
  cluster_type    = "multi-node"
  number_of_nodes = 2

  encrypted           = false
  publicly_accessible = false
  skip_final_snapshot = true

  snapshot_copy {
    destination_region = "us-east-2"
    retention_period   = var.snapshot_copy_retention_days
  }
}
