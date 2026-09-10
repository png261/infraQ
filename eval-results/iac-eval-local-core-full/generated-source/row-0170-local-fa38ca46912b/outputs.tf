output "vpc_id" {
  description = "ID of the VPC created for the DAX subnet group."
  value       = aws_vpc.dax.id
}

output "subnet_ids" {
  description = "Subnet IDs included in the custom DAX subnet group."
  value       = [aws_subnet.dax_a.id, aws_subnet.dax_b.id]
}

output "dax_subnet_group_name" {
  description = "Name of the custom DAX subnet group."
  value       = aws_dax_subnet_group.custom.name
}
