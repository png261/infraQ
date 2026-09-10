output "vpc_id" {
  description = "ID of the VPC created for Redshift."
  value       = aws_vpc.redshift.id
}

output "redshift_subnet_group_name" {
  description = "Name of the Redshift subnet group spanning us-east-1a and us-east-1b."
  value       = aws_redshift_subnet_group.redshift.name
}

output "redshift_cluster_identifier" {
  description = "Identifier of the Redshift cluster."
  value       = aws_redshift_cluster.redshift.cluster_identifier
}
