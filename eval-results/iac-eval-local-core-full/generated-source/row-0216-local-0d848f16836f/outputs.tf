output "vpc_id" {
  description = "ID of the VPC created for the Aurora PostgreSQL cluster."
  value       = aws_vpc.main.id
}

output "rds_cluster_id" {
  description = "ID of the Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.aurora_postgresql.id
}

output "rds_cluster_endpoint" {
  description = "Writer endpoint for the Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.aurora_postgresql.endpoint
}
