output "db_endpoint" {
  description = "Endpoint address and port for connecting to the PostgreSQL RDS instance."
  value       = aws_db_instance.postgres.endpoint
}
