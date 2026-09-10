output "db_instance_id" {
  description = "Identifier of the RDS DB instance."
  value       = aws_db_instance.database.id
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret managed by RDS for the master user password."
  value       = aws_db_instance.database.master_user_secret[0].secret_arn
  sensitive   = true
}
