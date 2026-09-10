output "vpc_id" {
  description = "ID of the VPC created for Aurora and the RDS Proxy."
  value       = aws_vpc.main.id
}

output "subnet_ids" {
  description = "Private subnet IDs used by the Aurora DB subnet group and RDS Proxy."
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "rds_cluster_endpoint" {
  description = "Aurora MySQL cluster writer endpoint."
  value       = aws_rds_cluster.aurora_mysql.endpoint
}

output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint for MySQL clients."
  value       = aws_db_proxy.mysql.endpoint
}

output "db_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials."
  value       = aws_secretsmanager_secret.db_credentials.arn
}
