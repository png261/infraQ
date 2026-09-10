output "connect_instance_id" {
  description = "ID of the Amazon Connect instance associated with the Lex bot."
  value       = aws_connect_instance.example.id
}

output "lex_bot_name" {
  description = "Name of the Amazon Lex bot associated with the Connect instance."
  value       = aws_lex_bot.example.name
}
