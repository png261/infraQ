output "dax_parameter_group_name" {
  description = "Name of the custom DAX parameter group."
  value       = aws_dax_parameter_group.this.name
}
