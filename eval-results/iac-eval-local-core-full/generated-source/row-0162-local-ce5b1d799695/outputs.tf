output "dynamodb_table_name" {
  description = "Name of the DynamoDB table with Contributor Insights enabled."
  value       = aws_dynamodb_table.benchmark.name
}

output "contributor_insights_enabled" {
  description = "Whether DynamoDB Contributor Insights is enabled for the table."
  value       = aws_dynamodb_contributor_insights.benchmark.enabled
}
