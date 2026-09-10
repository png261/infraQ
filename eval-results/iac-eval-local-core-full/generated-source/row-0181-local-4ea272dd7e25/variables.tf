variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "pipeline_name" {
  description = "Name of the SageMaker Pipeline."
  type        = string
  default     = "minimal-sagemaker-pipeline"

  validation {
    condition     = can(regex("^[A-Za-z0-9](-*[A-Za-z0-9]){0,255}$", var.pipeline_name))
    error_message = "The pipeline_name must be 1-256 characters and contain only alphanumeric characters and hyphens."
  }
}

variable "role_name" {
  description = "Name of the IAM role assumed by SageMaker Pipelines."
  type        = string
  default     = "minimal-sagemaker-pipeline-role"
}
