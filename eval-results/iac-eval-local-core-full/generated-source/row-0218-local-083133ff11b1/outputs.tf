output "rds_cluster_id" {
  description = "Identifier of the benchmark MySQL RDS cluster."
  value       = aws_rds_cluster.mysql.id
}

output "vpc_id" {
  description = "ID of the VPC created for the benchmark RDS cluster."
  value       = aws_vpc.main.id
}
