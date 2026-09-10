output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "database_subnet_ids" {
  description = "IDs of the database subnets."
  value       = aws_subnet.database[*].id
}

output "rds_cluster_endpoint" {
  description = "Writer endpoint of the Aurora MySQL cluster."
  value       = aws_rds_cluster.aurora_mysql.endpoint
}

output "rds_proxy_endpoint" {
  description = "Endpoint of the RDS proxy."
  value       = aws_db_proxy.aurora_mysql.endpoint
}

output "db_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret storing database credentials."
  value       = aws_secretsmanager_secret.db_credentials.arn
}
