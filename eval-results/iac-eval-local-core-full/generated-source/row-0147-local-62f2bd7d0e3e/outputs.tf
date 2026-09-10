output "redshift_cluster_id" {
  description = "Identifier of the Redshift cluster."
  value       = aws_redshift_cluster.this.id
}

output "redshift_cluster_arn" {
  description = "ARN of the Redshift cluster with the attached resource policy."
  value       = aws_redshift_cluster.this.arn
}
