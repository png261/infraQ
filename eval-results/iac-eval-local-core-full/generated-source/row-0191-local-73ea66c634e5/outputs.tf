output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}

output "instance_ids" {
  description = "IDs of the Amazon Linux instances."
  value       = aws_instance.linux[*].id
}

output "efs_file_system_id" {
  description = "ID of the shared EFS file system."
  value       = aws_efs_file_system.shared.id
}
