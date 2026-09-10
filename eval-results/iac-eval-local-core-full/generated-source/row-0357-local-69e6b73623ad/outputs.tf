output "vpc_id" {
  description = "ID of the VPC created for Aurora MySQL."
  value       = aws_vpc.main.id
}

output "rds_cluster_arn" {
  description = "ARN of the Aurora MySQL cluster."
  value       = aws_rds_cluster.aurora_mysql.arn
}

output "rds_proxy_endpoint" {
  description = "Endpoint of the RDS Proxy."
  value       = aws_db_proxy.mysql.endpoint
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials."
  value       = aws_secretsmanager_secret.db_credentials.arn
}
