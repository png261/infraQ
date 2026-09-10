output "sagemaker_model_name" {
  description = "Name of the SageMaker model used by the endpoint configuration."
  value       = aws_sagemaker_model.example.name
}

output "sagemaker_endpoint_configuration_name" {
  description = "Name of the SageMaker endpoint configuration."
  value       = aws_sagemaker_endpoint_configuration.example.name
}
