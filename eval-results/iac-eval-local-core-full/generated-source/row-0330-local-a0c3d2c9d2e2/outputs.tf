output "db_instance_identifier" {
  description = "Identifier of the PostgreSQL RDS instance."
  value       = aws_db_instance.postgres.identifier
}

output "db_instance_endpoint" {
  description = "Connection endpoint for the PostgreSQL RDS instance."
  value       = aws_db_instance.postgres.endpoint
}

output "db_subnet_ids" {
  description = "IDs of the database subnets."
  value       = aws_subnet.db[*].id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for RDS storage encryption."
  value       = aws_kms_key.postgres.arn
}
