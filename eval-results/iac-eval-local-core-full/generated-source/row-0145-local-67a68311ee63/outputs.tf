output "redshift_cluster_identifier" {
  description = "Identifier of the primary Redshift cluster in us-east-1."
  value       = aws_redshift_cluster.primary.cluster_identifier
}

output "redshift_snapshot_copy_destination_region" {
  description = "Destination region configured for automated snapshot copy replication."
  value       = aws_redshift_cluster.primary.snapshot_copy[0].destination_region
}
