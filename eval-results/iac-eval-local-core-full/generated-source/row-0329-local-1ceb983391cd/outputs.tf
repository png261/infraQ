output "vpc_id" {
  description = "ID of the benchmark VPC."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by the DB subnet group."
  value       = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

output "database_security_group_id" {
  description = "Security group ID attached to the MySQL database."
  value       = aws_security_group.database.id
}

output "db_instance_identifier" {
  description = "Identifier of the MySQL RDS instance."
  value       = aws_db_instance.database.identifier
}
