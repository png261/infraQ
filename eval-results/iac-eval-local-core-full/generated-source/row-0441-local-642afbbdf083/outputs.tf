output "vpc_id" {
  description = "ID of the VPC associated with the egress-only internet gateway."
  value       = aws_vpc.this.id
}

output "vpc_ipv6_cidr_block" {
  description = "AWS-assigned IPv6 CIDR block for the VPC."
  value       = aws_vpc.this.ipv6_cidr_block
}

output "egress_only_internet_gateway_id" {
  description = "ID of the egress-only internet gateway."
  value       = aws_egress_only_internet_gateway.this.id
}
