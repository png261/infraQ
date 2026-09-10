output "neptune_cluster_identifier" {
  description = "Identifier of the Neptune cluster."
  value       = aws_neptune_cluster.this.cluster_identifier
}

output "neptune_instance_identifier" {
  description = "Identifier of the Neptune cluster instance."
  value       = aws_neptune_cluster_instance.this.identifier
}
