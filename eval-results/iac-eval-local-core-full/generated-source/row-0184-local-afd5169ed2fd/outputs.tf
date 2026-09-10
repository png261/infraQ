output "sagemaker_endpoint_name" {
  description = "Name of the SageMaker endpoint."
  value       = aws_sagemaker_endpoint.this.name
}

output "sagemaker_endpoint_arn" {
  description = "ARN of the SageMaker endpoint."
  value       = aws_sagemaker_endpoint.this.arn
}

output "sagemaker_model_name" {
  description = "Name of the SageMaker model used by the endpoint."
  value       = aws_sagemaker_model.this.name
}
