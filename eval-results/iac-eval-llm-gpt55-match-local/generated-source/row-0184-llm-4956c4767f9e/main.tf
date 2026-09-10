terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the SageMaker endpoint will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for SageMaker resources."
  type        = string
  default     = "demo-sagemaker-endpoint"
}

variable "sagemaker_instance_type" {
  description = "Instance type for the SageMaker endpoint."
  type        = string
  default     = "ml.m5.large"
}

variable "initial_instance_count" {
  description = "Initial number of instances for the SageMaker endpoint."
  type        = number
  default     = 1
}

variable "huggingface_model_id" {
  description = "Hugging Face model ID to deploy."
  type        = string
  default     = "distilbert-base-uncased-finetuned-sst-2-english"
}

variable "huggingface_task" {
  description = "Hugging Face task type."
  type        = string
  default     = "text-classification"
}

variable "huggingface_inference_image" {
  description = "Hugging Face SageMaker inference container image URI."
  type        = string
  default     = "763104351884.dkr.ecr.us-east-1.amazonaws.com/huggingface-pytorch-inference:2.1.0-transformers4.37.0-cpu-py310-ubuntu22.04"
}

resource "aws_iam_role" "sagemaker_execution_role" {
  name = "${var.project_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_sagemaker_model" "model" {
  name               = "${var.project_name}-model"
  execution_role_arn = aws_iam_role.sagemaker_execution_role.arn

  primary_container {
    image = var.huggingface_inference_image

    environment = {
      HF_MODEL_ID = var.huggingface_model_id
      HF_TASK     = var.huggingface_task
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.sagemaker_full_access
  ]
}

resource "aws_sagemaker_endpoint_configuration" "endpoint_config" {
  name = "${var.project_name}-endpoint-config"

  production_variants {
    variant_name           = "AllTraffic"
    model_name             = aws_sagemaker_model.model.name
    initial_instance_count = var.initial_instance_count
    instance_type          = var.sagemaker_instance_type
    initial_variant_weight = 1
  }
}

resource "aws_sagemaker_endpoint" "endpoint" {
  name                 = "${var.project_name}-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.endpoint_config.name
}

output "sagemaker_endpoint_name" {
  description = "Name of the SageMaker endpoint."
  value       = aws_sagemaker_endpoint.endpoint.name
}

output "sagemaker_endpoint_arn" {
  description = "ARN of the SageMaker endpoint."
  value       = aws_sagemaker_endpoint.endpoint.arn
}

output "sagemaker_model_name" {
  description = "Name of the SageMaker model."
  value       = aws_sagemaker_model.model.name
}

output "sagemaker_execution_role_arn" {
  description = "ARN of the SageMaker execution role."
  value       = aws_iam_role.sagemaker_execution_role.arn
}