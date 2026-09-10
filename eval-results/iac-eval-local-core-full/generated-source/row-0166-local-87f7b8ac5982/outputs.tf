output "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  value       = aws_dynamodb_table.benchmark.name
}

output "dynamodb_item_hash_key" {
  description = "Hash key used by the DynamoDB table item."
  value       = aws_dynamodb_table_item.benchmark.hash_key
}
