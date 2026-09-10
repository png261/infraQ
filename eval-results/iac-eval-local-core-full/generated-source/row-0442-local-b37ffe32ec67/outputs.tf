output "vpc_id" {
  description = "ID of the VPC associated with the pike DHCP options."
  value       = aws_vpc.specified.id
}

output "dhcp_options_id" {
  description = "ID of the pike DHCP options set."
  value       = aws_vpc_dhcp_options.pike.id
}
