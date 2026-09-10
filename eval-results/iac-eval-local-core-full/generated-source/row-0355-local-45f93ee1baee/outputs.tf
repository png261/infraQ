output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group."
  value       = aws_db_subnet_group.database.name
}

output "rds_cluster_endpoint" {
  description = "Writer endpoint for the Aurora MySQL cluster."
  value       = aws_rds_cluster.aurora.endpoint
}

output "rds_proxy_endpoint" {
  description = "Endpoint for the RDS proxy."
  value       = aws_db_proxy.aurora.endpoint
}

output "db_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials."
  value       = aws_secretsmanager_secret.db_credentials.arn
}
