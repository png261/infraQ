output "database_endpoint" {
  description = "Endpoint for connecting to the benchmark PostgreSQL RDS instance."
  value       = aws_db_instance.postgres.endpoint
}
