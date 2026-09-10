output "sagemaker_pipeline_name" {
  description = "Name of the SageMaker Pipeline."
  value       = aws_sagemaker_pipeline.this.pipeline_name
}

output "sagemaker_pipeline_arn" {
  description = "ARN of the SageMaker Pipeline."
  value       = aws_sagemaker_pipeline.this.arn
}

output "sagemaker_pipeline_role_arn" {
  description = "ARN of the IAM role used by the SageMaker Pipeline."
  value       = aws_iam_role.sagemaker_pipeline.arn
}

output "prebuilt_ecr_image_uri" {
  description = "Resolved SageMaker prebuilt ECR image URI."
  value       = data.aws_sagemaker_prebuilt_ecr_image.sklearn.registry_path
}
