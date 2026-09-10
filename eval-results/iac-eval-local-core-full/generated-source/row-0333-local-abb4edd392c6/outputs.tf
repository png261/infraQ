output "db_instance_identifier" {
  description = "Identifier of the PostgreSQL RDS instance."
  value       = aws_db_instance.postgres.identifier
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group."
  value       = aws_db_subnet_group.postgres.name
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for RDS storage encryption."
  value       = aws_kms_key.postgres.arn
}
