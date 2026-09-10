output "kinesis_stream_name" {
  description = "Name of the Kinesis stream used as the analytics application input."
  value       = aws_kinesis_stream.input.name
}

output "kinesis_analytics_application_name" {
  description = "Name of the Kinesis Analytics application."
  value       = aws_kinesis_analytics_application.this.name
}
