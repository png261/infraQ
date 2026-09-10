output "kinesisanalyticsv2_application_name" {
  description = "Name of the Kinesis Data Analytics v2 Apache Flink application."
  value       = aws_kinesisanalyticsv2_application.flink.name
}

output "kinesisanalyticsv2_application_arn" {
  description = "ARN of the Kinesis Data Analytics v2 Apache Flink application."
  value       = aws_kinesisanalyticsv2_application.flink.arn
}

output "service_execution_role_arn" {
  description = "ARN of the IAM role used by the Kinesis Data Analytics v2 application."
  value       = aws_iam_role.kinesis_analytics.arn
}
