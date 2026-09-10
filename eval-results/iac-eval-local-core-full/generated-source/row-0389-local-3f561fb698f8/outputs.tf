output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.app.dns_name
}

output "vpc_id" {
  description = "ID of the benchmark VPC."
  value       = aws_vpc.main.id
}
