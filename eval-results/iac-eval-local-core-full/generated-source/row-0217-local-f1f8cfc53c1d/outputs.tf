output "vpc_id" {
  description = "ID of the VPC created for the benchmark."
  value       = aws_vpc.main.id
}

output "rds_cluster_id" {
  description = "ID of the benchmark MySQL RDS cluster."
  value       = aws_rds_cluster.mysql.id
}
