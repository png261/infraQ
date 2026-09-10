output "sns_topic_arn" {
  description = "ARN of the SNS topic receiving Redshift event notifications."
  value       = aws_sns_topic.redshift_events.arn
}

output "redshift_cluster_id" {
  description = "Identifier of the Redshift cluster."
  value       = aws_redshift_cluster.this.id
}
