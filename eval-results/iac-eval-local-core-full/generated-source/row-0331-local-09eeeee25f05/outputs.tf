output "db_instance_id" {
  description = "Identifier of the PostgreSQL RDS instance."
  value       = aws_db_instance.postgres.id
}

output "db_instance_endpoint" {
  description = "Connection endpoint for the PostgreSQL RDS instance."
  value       = aws_db_instance.postgres.endpoint
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for RDS storage encryption."
  value       = aws_kms_key.postgres.arn
}
