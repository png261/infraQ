output "db_instance_identifier" {
  description = "Identifier of the MySQL DB instance."
  value       = aws_db_instance.mysql.identifier
}

output "vpc_id" {
  description = "ID of the VPC created for the MySQL instance."
  value       = aws_vpc.main.id
}
