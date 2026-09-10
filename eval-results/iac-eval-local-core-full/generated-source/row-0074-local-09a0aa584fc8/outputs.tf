output "kendra_index_id" {
  description = "ID of the Amazon Kendra index."
  value       = aws_kendra_index.this.id
}

output "kendra_data_source_id" {
  description = "ID of the Amazon Kendra data source."
  value       = aws_kendra_data_source.this.id
}
