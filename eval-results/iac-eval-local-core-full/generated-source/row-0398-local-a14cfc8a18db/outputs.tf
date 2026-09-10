output "load_balancer_dns_name" {
  description = "DNS name of the application load balancer."
  value       = aws_lb.app.dns_name
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito user pool used by the ALB listener authentication action."
  value       = aws_cognito_user_pool.main.id
}
