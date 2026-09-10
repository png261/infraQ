output "load_balancer_dns_name" {
  description = "DNS name of the application load balancer."
  value       = aws_lb.app.dns_name
}
