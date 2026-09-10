output "elasticache_user_group_id" {
  description = "ID of the created ElastiCache user group."
  value       = aws_elasticache_user_group.benchmark.user_group_id
}

output "elasticache_default_user_id" {
  description = "ID of the created default ElastiCache user included when the group is created."
  value       = aws_elasticache_user.default.user_id
}

output "elasticache_application_user_id" {
  description = "ID of the created ElastiCache application user associated with the group."
  value       = aws_elasticache_user.application.user_id
}
