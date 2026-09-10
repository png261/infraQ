output "notebook_instance_name" {
  description = "Name of the SageMaker notebook instance."
  value       = aws_sagemaker_notebook_instance.this.name
}

output "code_repository_name" {
  description = "Name of the SageMaker code repository cloned by default."
  value       = aws_sagemaker_code_repository.terraform_provider_aws.code_repository_name
}

output "prebuilt_ecr_image_uri" {
  description = "SageMaker prebuilt ECR image URI looked up for benchmark coverage."
  value       = data.aws_sagemaker_prebuilt_ecr_image.notebook_base.registry_path
}
