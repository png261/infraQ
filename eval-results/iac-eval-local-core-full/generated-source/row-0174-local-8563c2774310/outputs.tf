output "sagemaker_domain_id" {
  description = "ID of the SageMaker domain created for the space."
  value       = aws_sagemaker_domain.this.id
}

output "sagemaker_space_name" {
  description = "Name of the SageMaker space."
  value       = aws_sagemaker_space.this.space_name
}
