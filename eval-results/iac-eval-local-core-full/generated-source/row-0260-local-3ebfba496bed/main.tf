resource "aws_sns_topic" "redshift_parameter_group_events" {
  name = "example-redshift-parameter-group-events"
}

resource "aws_redshift_parameter_group" "example" {
  name   = "example-redshift-parameter-group"
  family = "redshift-1.0"

  parameter {
    name  = "enable_user_activity_logging"
    value = "true"
  }
}

resource "aws_redshift_cluster" "example" {
  cluster_identifier          = "example-redshift-cluster"
  database_name               = "exampledb"
  master_username             = var.redshift_master_username
  master_password             = var.redshift_master_password
  node_type                   = "dc2.large"
  cluster_type                = "single-node"
  cluster_parameter_group_name = aws_redshift_parameter_group.example.id
  skip_final_snapshot         = true
}

resource "aws_redshift_event_subscription" "parameter_group_events" {
  name          = "example-redshift-parameter-group-events"
  source_type   = "cluster-parameter-group"
  source_ids    = [aws_redshift_parameter_group.example.id]
  sns_topic_arn = aws_sns_topic.redshift_parameter_group_events.arn

  event_categories = ["configuration"]
  severity         = "INFO"
  enabled          = true
}
