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
  description = "AWS region to deploy SageMaker resources into."
  type        = string
  default     = "us-east-1"
}

variable "sagemaker_model_name" {
  description = "Name of the SageMaker model."
  type        = string
  default     = "example-sagemaker-model"
}

variable "endpoint_config_name" {
  description = "Name of the SageMaker endpoint configuration."
  type        = string
  default     = "example-sagemaker-endpoint-config"
}

variable "container_image" {
  description = "Container image URI for the SageMaker model."
  type        = string
  default     = "683313688378.dkr.ecr.us-east-1.amazonaws.com/sagemaker-xgboost:1.7-1"
}

variable "instance_type" {
  description = "Instance type for the SageMaker endpoint production variant."
  type        = string
  default     = "ml.m5.large"
}

variable "initial_instance_count" {
  description = "Initial number of instances for the production variant."
  type        = number
  default     = 1
}

resource "aws_iam_role" "sagemaker_execution_role" {
  name = "example-sagemaker-execution-role"

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
  name               = var.sagemaker_model_name
  execution_role_arn = aws_iam_role.sagemaker_execution_role.arn

  primary_container {
    image = var.container_image
  }

  depends_on = [
    aws_iam_role_policy_attachment.sagemaker_full_access
  ]
}

resource "aws_sagemaker_endpoint_configuration" "endpoint_config" {
  name = var.endpoint_config_name

  production_variants {
    variant_name           = "AllTraffic"
    model_name             = aws_sagemaker_model.model.name
    initial_instance_count = var.initial_instance_count
    instance_type          = var.instance_type
    initial_variant_weight = 1
  }

  tags = {
    Name        = var.endpoint_config_name
    Environment = "example"
    ManagedBy   = "terraform"
  }
}