output "sagemaker_domain_id" {
  description = "ID of the SageMaker domain."
  value       = aws_sagemaker_domain.jupyter.id
}

output "sagemaker_user_profile_name" {
  description = "Name of the SageMaker user profile."
  value       = aws_sagemaker_user_profile.jupyter.user_profile_name
}

output "sagemaker_app_arn" {
  description = "ARN of the JupyterServer SageMaker app."
  value       = aws_sagemaker_app.jupyter_server.arn
}
