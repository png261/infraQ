output "elasticache_user_id" {
  description = "ID of the ElastiCache IAM-authenticated Redis user."
  value       = aws_elasticache_user.iam_user.user_id
}

output "elasticache_user_name" {
  description = "Name of the ElastiCache IAM-authenticated Redis user."
  value       = aws_elasticache_user.iam_user.user_name
}
