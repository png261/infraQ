output "sagemaker_domain_id" {
  description = "The ID of the SageMaker Domain."
  value       = aws_sagemaker_domain.this.id
}

output "sagemaker_domain_arn" {
  description = "The ARN of the SageMaker Domain."
  value       = aws_sagemaker_domain.this.arn
}

output "sagemaker_vpc_id" {
  description = "The ID of the VPC created for the SageMaker Domain."
  value       = aws_vpc.sagemaker.id
}

output "sagemaker_subnet_id" {
  description = "The ID of the subnet created for the SageMaker Domain."
  value       = aws_subnet.sagemaker.id
}
