terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the SageMaker Pipeline will be created."
  type        = string
  default     = "us-east-1"
}

variable "pipeline_name_prefix" {
  description = "Prefix for the SageMaker Pipeline name."
  type        = string
  default     = "example-sagemaker-pipeline"
}

resource "random_id" "suffix" {
  byte_length = 4
}

data "aws_iam_policy_document" "sagemaker_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "sagemaker_pipeline_execution_role" {
  name               = "${var.pipeline_name_prefix}-execution-role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_pipeline_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_sagemaker_pipeline" "this" {
  pipeline_name         = "${var.pipeline_name_prefix}-${random_id.suffix.hex}"
  pipeline_display_name = "Example SageMaker Pipeline"
  role_arn              = aws_iam_role.sagemaker_pipeline_execution_role.arn

  pipeline_definition = jsonencode({
    Version = "2020-12-01"

    Metadata = {
      Description = "Minimal SageMaker Pipeline created with Terraform"
    }

    Parameters = []

    Steps = [
      {
        Name = "ExampleFailStep"
        Type = "Fail"

        Arguments = {
          ErrorMessage = "This is a placeholder SageMaker Pipeline step. Replace it with processing, training, transform, or model registration steps."
        }
      }
    ]
  })

  tags = {
    Name        = "${var.pipeline_name_prefix}-${random_id.suffix.hex}"
    Environment = "example"
    ManagedBy   = "Terraform"
  }

  depends_on = [
    aws_iam_role_policy_attachment.sagemaker_full_access
  ]
}

output "sagemaker_pipeline_name" {
  description = "Name of the created SageMaker Pipeline."
  value       = aws_sagemaker_pipeline.this.pipeline_name
}

output "sagemaker_pipeline_arn" {
  description = "ARN of the created SageMaker Pipeline."
  value       = aws_sagemaker_pipeline.this.arn
}

output "sagemaker_pipeline_execution_role_arn" {
  description = "ARN of the IAM role used by the SageMaker Pipeline."
  value       = aws_iam_role.sagemaker_pipeline_execution_role.arn
}