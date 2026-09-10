output "global_table_name" {
  description = "Name of the primary DynamoDB global table."
  value       = aws_dynamodb_table.global.name
}

output "global_table_arn" {
  description = "ARN of the primary DynamoDB global table used to create the replica."
  value       = aws_dynamodb_table.global.arn
}

output "replica_region" {
  description = "AWS region where the DynamoDB table replica is created."
  value       = "us-west-2"
}
