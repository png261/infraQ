output "db_instance_identifier" {
  description = "Identifier of the PostgreSQL RDS instance."
  value       = aws_db_instance.postgres.identifier
}

output "db_instance_endpoint" {
  description = "Connection endpoint for the PostgreSQL RDS instance."
  value       = aws_db_instance.postgres.endpoint
}

output "db_subnet_group_name" {
  description = "Name of the RDS subnet group used by the PostgreSQL instance."
  value       = aws_db_subnet_group.airbyte_tests.name
}

output "vpc_id" {
  description = "ID of the VPC hosting the Airbyte connector test RDS instance."
  value       = aws_vpc.airbyte_tests.id
}
