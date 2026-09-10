output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.main.dns_name
}

output "instance_id" {
  description = "ID of the registered target instance."
  value       = aws_instance.main.id
}
