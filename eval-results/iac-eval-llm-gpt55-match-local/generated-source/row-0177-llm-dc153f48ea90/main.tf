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
  description = "AWS region where the SageMaker Image will be created."
  type        = string
  default     = "us-east-1"
}

variable "sagemaker_image_name" {
  description = "Name of the SageMaker Image."
  type        = string
  default     = "example-sagemaker-image"
}

variable "sagemaker_image_display_name" {
  description = "Display name for the SageMaker Image."
  type        = string
  default     = "Example SageMaker Image"
}

variable "sagemaker_image_description" {
  description = "Description of the SageMaker Image."
  type        = string
  default     = "A custom AWS SageMaker Image created with Terraform."
}

resource "aws_iam_role" "sagemaker_image_role" {
  name = "example-sagemaker-image-role"

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

  tags = {
    Name        = "example-sagemaker-image-role"
    Environment = "example"
  }
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_image_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_sagemaker_image" "example" {
  image_name   = var.sagemaker_image_name
  role_arn     = aws_iam_role.sagemaker_image_role.arn
  display_name = var.sagemaker_image_display_name
  description  = var.sagemaker_image_description

  depends_on = [
    aws_iam_role_policy_attachment.sagemaker_full_access
  ]

  tags = {
    Name        = var.sagemaker_image_name
    Environment = "example"
  }
}

output "sagemaker_image_name" {
  description = "The name of the SageMaker Image."
  value       = aws_sagemaker_image.example.image_name
}

output "sagemaker_image_arn" {
  description = "The ARN of the SageMaker Image."
  value       = aws_sagemaker_image.example.arn
}

output "sagemaker_image_role_arn" {
  description = "The ARN of the IAM role associated with the SageMaker Image."
  value       = aws_iam_role.sagemaker_image_role.arn
}