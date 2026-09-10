output "vpc_id" {
  description = "VPC ID created for the Chapter 4 drift demonstration."
  value       = aws_vpc.chapter4_demo.id
}

output "security_group_id" {
  description = "Security group ID used for manual drift and policy violation."
  value       = aws_security_group.chapter4_demo.id
}
