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
  description = "AWS region where the DAX parameter group will be created."
  type        = string
  default     = "us-east-1"
}

variable "dax_parameter_group_name" {
  description = "Name of the DAX parameter group."
  type        = string
  default     = "example-dax-parameter-group"
}

resource "aws_dax_parameter_group" "example" {
  name        = var.dax_parameter_group_name
  description = "Example DAX parameter group managed by Terraform"

  parameters {
    name  = "query-ttl-millis"
    value = "300000"
  }

  parameters {
    name  = "record-ttl-millis"
    value = "300000"
  }
}

output "dax_parameter_group_name" {
  description = "The name of the created DAX parameter group."
  value       = aws_dax_parameter_group.example.name
}

output "dax_parameter_group_id" {
  description = "The ID of the created DAX parameter group."
  value       = aws_dax_parameter_group.example.id
}