output "redshift_cluster_identifier" {
  description = "Identifier of the Redshift cluster."
  value       = aws_redshift_cluster.example.cluster_identifier
}

output "redshift_cluster_endpoint" {
  description = "Endpoint address of the Redshift cluster."
  value       = aws_redshift_cluster.example.endpoint
}

output "redshift_iam_role_arn" {
  description = "ARN of the IAM role associated with the Redshift cluster."
  value       = aws_iam_role.redshift.arn
}
