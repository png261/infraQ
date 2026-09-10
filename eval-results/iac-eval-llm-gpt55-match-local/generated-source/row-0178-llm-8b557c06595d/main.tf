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
  description = "AWS region where the SageMaker model will be created."
  type        = string
  default     = "us-east-1"
}

variable "sagemaker_model_name" {
  description = "Name of the SageMaker model."
  type        = string
  default     = "kmeans-sagemaker-model"
}

variable "kmeans_image_uri" {
  description = "AWS SageMaker built-in K-Means container image URI for us-east-1."
  type        = string
  default     = "382416733822.dkr.ecr.us-east-1.amazonaws.com/kmeans:1"
}

resource "aws_iam_role" "sagemaker_execution_role" {
  name = "sagemaker-kmeans-execution-role"

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

resource "aws_sagemaker_model" "kmeans_model" {
  name               = var.sagemaker_model_name
  execution_role_arn = aws_iam_role.sagemaker_execution_role.arn

  primary_container {
    image = var.kmeans_image_uri
  }

  depends_on = [
    aws_iam_role_policy_attachment.sagemaker_full_access
  ]
}

output "sagemaker_model_name" {
  description = "The name of the SageMaker K-Means model."
  value       = aws_sagemaker_model.kmeans_model.name
}

output "sagemaker_model_arn" {
  description = "The ARN of the SageMaker K-Means model."
  value       = aws_sagemaker_model.kmeans_model.arn
}

output "sagemaker_execution_role_arn" {
  description = "The ARN of the SageMaker execution role."
  value       = aws_iam_role.sagemaker_execution_role.arn
}