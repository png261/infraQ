output "vpc_id" {
  description = "ID of the example VPC."
  value       = aws_vpc.example.id
}

output "subnet_ids" {
  description = "IDs of the example subnets in the Neptune subnet group."
  value       = [aws_subnet.example_a.id, aws_subnet.example_b.id]
}

output "neptune_subnet_group_name" {
  description = "Name of the Neptune subnet group."
  value       = aws_neptune_subnet_group.example.name
}
