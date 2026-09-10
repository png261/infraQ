output "sagemaker_image_arn" {
  description = "ARN of the SageMaker image."
  value       = aws_sagemaker_image.example.arn
}

output "sagemaker_image_execution_role_arn" {
  description = "ARN of the IAM role used by the SageMaker image."
  value       = aws_iam_role.sagemaker_image_execution.arn
}
