terraform {
  required_version = ">= 1.6.0"

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

resource "aws_sns_topic" "redshift_events" {
  name = "redshift-cluster-events"
}

resource "aws_redshift_cluster" "this" {
  cluster_identifier = "example-redshift-cluster"
  database_name      = "exampledb"
  master_username    = "adminuser"
  master_password    = var.redshift_master_password
  node_type          = "dc2.large"
  cluster_type       = "single-node"

  encrypted                           = true
  publicly_accessible                 = false
  skip_final_snapshot                 = true
  automated_snapshot_retention_period = 1
}

resource "aws_redshift_event_subscription" "cluster_events" {
  name          = "redshift-cluster-event-subscription"
  source_type   = "cluster"
  source_ids    = [aws_redshift_cluster.this.id]
  sns_topic_arn = aws_sns_topic.redshift_events.arn

  enabled  = true
  severity = "INFO"
}
