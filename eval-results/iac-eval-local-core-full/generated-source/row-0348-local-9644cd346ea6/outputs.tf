output "vpc_id" {
  description = "ID of the custom VPC."
  value       = aws_vpc.main.id
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group."
  value       = aws_db_subnet_group.database.name
}

output "db_instance_identifier" {
  description = "Identifier of the PostgreSQL DB instance."
  value       = aws_db_instance.postgres.identifier
}
