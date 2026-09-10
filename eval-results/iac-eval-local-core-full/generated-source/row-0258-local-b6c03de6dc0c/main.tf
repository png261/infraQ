resource "aws_sns_topic" "redshift_events" {
  name = "redshift-cluster-events"
}

resource "aws_redshift_cluster" "example" {
  cluster_identifier  = "example-redshift-cluster"
  database_name       = "exampledb"
  master_username     = "adminuser"
  master_password     = var.redshift_master_password
  node_type           = "dc2.large"
  cluster_type        = "single-node"
  skip_final_snapshot = true
}

resource "aws_redshift_event_subscription" "cluster_events" {
  name          = "example-redshift-cluster-events"
  sns_topic_arn = aws_sns_topic.redshift_events.arn
  source_type   = "cluster"
  source_ids    = [aws_redshift_cluster.example.cluster_identifier]
}
