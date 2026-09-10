terraform {
  required_version = ">= 1.0"

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
  description = "AWS region where the SageMaker notebook instance will be created."
  type        = string
  default     = "us-east-1"
}

variable "notebook_instance_name" {
  description = "Name of the SageMaker notebook instance."
  type        = string
  default     = "example-sagemaker-notebook"
}

variable "notebook_instance_type" {
  description = "Instance type for the SageMaker notebook instance."
  type        = string
  default     = "ml.t2.medium"
}

data "aws_iam_policy_document" "sagemaker_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "sagemaker_notebook_role" {
  name               = "${var.notebook_instance_name}-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_notebook_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_sagemaker_notebook_instance" "notebook" {
  name          = var.notebook_instance_name
  role_arn      = aws_iam_role.sagemaker_notebook_role.arn
  instance_type = var.notebook_instance_type

  depends_on = [
    aws_iam_role_policy_attachment.sagemaker_full_access
  ]

  tags = {
    Name        = var.notebook_instance_name
    Environment = "example"
    ManagedBy   = "terraform"
  }
}

output "sagemaker_notebook_instance_name" {
  description = "The name of the SageMaker notebook instance."
  value       = aws_sagemaker_notebook_instance.notebook.name
}

output "sagemaker_notebook_instance_arn" {
  description = "The ARN of the SageMaker notebook instance."
  value       = aws_sagemaker_notebook_instance.notebook.arn
}

output "sagemaker_notebook_role_arn" {
  description = "The ARN of the IAM role used by the SageMaker notebook instance."
  value       = aws_iam_role.sagemaker_notebook_role.arn
}