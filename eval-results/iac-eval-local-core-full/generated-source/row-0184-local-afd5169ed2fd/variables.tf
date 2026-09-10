variable "name_prefix" {
  description = "Prefix used for SageMaker resource names."
  type        = string
  default     = "iac-eval-sagemaker"

  validation {
    condition     = can(regex("^[a-zA-Z0-9](-*[a-zA-Z0-9]){0,31}$", var.name_prefix))
    error_message = "name_prefix must be 1-32 characters, start and end with an alphanumeric character, and contain only alphanumeric characters and hyphens."
  }
}

variable "sagemaker_image_repository_name" {
  description = "Name of the SageMaker prebuilt ECR image repository to use."
  type        = string
  default     = "sagemaker-xgboost"
}

variable "sagemaker_image_tag" {
  description = "Version tag for the SageMaker prebuilt image."
  type        = string
  default     = "1.7-1"
}

variable "instance_type" {
  description = "Instance type for the SageMaker endpoint production variant."
  type        = string
  default     = "ml.m5.large"
}

variable "initial_instance_count" {
  description = "Initial number of instances for the SageMaker endpoint production variant."
  type        = number
  default     = 1

  validation {
    condition     = var.initial_instance_count >= 1
    error_message = "initial_instance_count must be at least 1."
  }
}
