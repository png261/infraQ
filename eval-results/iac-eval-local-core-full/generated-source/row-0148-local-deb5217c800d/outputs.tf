output "redshift_cluster_identifier" {
  description = "Identifier of the Redshift cluster."
  value       = aws_redshift_cluster.redshift.cluster_identifier
}

output "redshift_endpoint_name" {
  description = "Name of the Redshift endpoint access resource."
  value       = aws_redshift_endpoint_access.redshift.endpoint_name
}

output "redshift_subnet_group_name" {
  description = "Name of the Redshift subnet group."
  value       = aws_redshift_subnet_group.redshift.name
}
