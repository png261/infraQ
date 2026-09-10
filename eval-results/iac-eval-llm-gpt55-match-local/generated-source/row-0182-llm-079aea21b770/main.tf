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
  description = "AWS region where the SageMaker Human Task UI will be created."
  type        = string
  default     = "us-east-1"
}

variable "human_task_ui_name" {
  description = "Name of the SageMaker Human Task UI."
  type        = string
  default     = "test-human-task-ui"
}

resource "aws_sagemaker_human_task_ui" "test" {
  human_task_ui_name = var.human_task_ui_name

  ui_template {
    content = <<-HTML
<h1>
    TEST
</h1>
HTML
  }
}

output "human_task_ui_arn" {
  description = "ARN of the created SageMaker Human Task UI."
  value       = aws_sagemaker_human_task_ui.test.arn
}

output "human_task_ui_name" {
  description = "Name of the created SageMaker Human Task UI."
  value       = aws_sagemaker_human_task_ui.test.human_task_ui_name
}