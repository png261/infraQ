output "vpc_id" {
  description = "ID of the VPC created for the Aurora MySQL cluster."
  value       = aws_vpc.main.id
}

output "rds_cluster_identifier" {
  description = "Identifier of the Aurora MySQL cluster."
  value       = aws_rds_cluster.aurora_mysql.cluster_identifier
}

output "rds_cluster_endpoint" {
  description = "Writer endpoint of the Aurora MySQL cluster."
  value       = aws_rds_cluster.aurora_mysql.endpoint
}
