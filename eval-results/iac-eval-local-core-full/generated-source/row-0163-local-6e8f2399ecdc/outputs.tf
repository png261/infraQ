output "global_table_name" {
  description = "Name of the DynamoDB global table."
  value       = aws_dynamodb_global_table.this.name
}

output "replica_regions" {
  description = "Regions participating in the DynamoDB Global Table v1."
  value       = [for replica in aws_dynamodb_global_table.this.replica : replica.region_name]
}
