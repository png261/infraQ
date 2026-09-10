output "load_balancer_dns_name" {
  description = "DNS name of the application load balancer."
  value       = aws_lb.main.dns_name
}

output "fixed_response_listener_arn" {
  description = "ARN of the HTTP listener returning the fixed response."
  value       = aws_lb_listener.http.arn
}
