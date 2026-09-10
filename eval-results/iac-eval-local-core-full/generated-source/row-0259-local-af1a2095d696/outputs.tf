output "redshift_cluster_identifier" {
  description = "Identifier of the example Redshift cluster."
  value       = aws_redshift_cluster.example.cluster_identifier
}

output "redshift_parameter_group_name" {
  description = "Name of the Redshift parameter group associated with event notifications."
  value       = aws_redshift_parameter_group.example.id
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic receiving Redshift parameter group events."
  value       = aws_sns_topic.redshift_parameter_group_events.arn
}
