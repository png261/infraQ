output "vpc_id" {
  description = "ID of the VPC created for the Aurora MySQL cluster."
  value       = aws_vpc.main.id
}

output "rds_cluster_identifier" {
  description = "Identifier of the Aurora MySQL cluster."
  value       = aws_rds_cluster.aurora.cluster_identifier
}

output "db_proxy_endpoint" {
  description = "Endpoint of the RDS DB proxy."
  value       = aws_db_proxy.mysql.endpoint
}
