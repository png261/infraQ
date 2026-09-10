output "db_instance_id" {
  description = "Identifier of the RDS instance."
  value       = aws_db_instance.airbyte.id
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group used by the RDS instance."
  value       = aws_db_subnet_group.airbyte.name
}

output "vpc_id" {
  description = "ID of the VPC containing the RDS instance."
  value       = aws_vpc.airbyte.id
}
