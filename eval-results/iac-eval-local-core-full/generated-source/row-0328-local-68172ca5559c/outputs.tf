output "vpc_id" {
  description = "ID of the DolphinScheduler VPC."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by the DB subnet group."
  value       = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

output "database_security_group_id" {
  description = "Security group ID attached to the PostgreSQL database."
  value       = aws_security_group.database.id
}

output "database_endpoint" {
  description = "PostgreSQL RDS endpoint."
  value       = aws_db_instance.database.endpoint
}
