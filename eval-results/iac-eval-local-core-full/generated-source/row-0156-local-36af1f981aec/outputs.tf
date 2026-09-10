output "lambda_function_name" {
  description = "Name of the Lambda function invoked by EventBridge."
  value       = aws_lambda_function.test_lambda.function_name
}

output "event_rule_name" {
  description = "Name of the EventBridge rule matching EC2 CreateImage events."
  value       = aws_cloudwatch_event_rule.ec2_image_created.name
}
