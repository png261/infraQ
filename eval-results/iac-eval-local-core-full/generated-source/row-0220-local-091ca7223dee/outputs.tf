output "db_instance_id" {
  description = "Identifier of the PostgreSQL DB instance."
  value       = aws_db_instance.postgres.id
}

output "db_instance_endpoint" {
  description = "Connection endpoint for the PostgreSQL DB instance."
  value       = aws_db_instance.postgres.endpoint
}
