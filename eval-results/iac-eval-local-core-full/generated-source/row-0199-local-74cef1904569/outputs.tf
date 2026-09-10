output "dax_cluster_name" {
  description = "Name of the DAX cluster."
  value       = aws_dax_cluster.this.cluster_name
}

output "dax_iam_role_arn" {
  description = "IAM role ARN used by the DAX cluster."
  value       = aws_iam_role.dax.arn
}
