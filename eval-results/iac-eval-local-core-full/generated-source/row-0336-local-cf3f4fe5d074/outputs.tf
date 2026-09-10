output "db_instance_endpoint" {
  description = "RDS PostgreSQL endpoint for Airbyte connector tests."
  value       = aws_db_instance.airbyte.endpoint
}

output "db_subnet_group_name" {
  description = "DB subnet group used by the RDS instance."
  value       = aws_db_subnet_group.airbyte.name
}

output "rds_security_group_id" {
  description = "Security group attached to the RDS instance."
  value       = aws_security_group.rds.id
}
