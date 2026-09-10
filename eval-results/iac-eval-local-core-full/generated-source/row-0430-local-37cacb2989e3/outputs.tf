output "vpc_id" {
  description = "ID of the dedicated-tenancy VPC."
  value       = aws_vpc.this.id
}

output "internet_gateway_id" {
  description = "ID of the internet gateway attached to the VPC."
  value       = aws_internet_gateway.this.id
}

output "route_table_id" {
  description = "ID of the route table with outbound internet access."
  value       = aws_route_table.this.id
}
