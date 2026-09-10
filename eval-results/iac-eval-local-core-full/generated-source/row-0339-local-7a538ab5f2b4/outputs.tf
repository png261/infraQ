output "db_endpoint" {
  description = "Endpoint for connecting to the MySQL RDS instance."
  value       = aws_db_instance.mysql.endpoint
}
