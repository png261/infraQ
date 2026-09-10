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
  description = "Name of the custom DAX parameter group."
  type        = string
  default     = "custom-dax-parameter-group"
}

variable "query_ttl_millis" {
  description = "Default time-to-live, in milliseconds, for query results cached by DAX."
  type        = string
  default     = "60000"
}

variable "record_ttl_millis" {
  description = "Default time-to-live, in milliseconds, for individual records cached by DAX."
  type        = string
  default     = "300000"
}

resource "aws_dax_parameter_group" "custom" {
  name = var.dax_parameter_group_name

  parameters {
    name  = "query-ttl-millis"
    value = var.query_ttl_millis
  }

  parameters {
    name  = "record-ttl-millis"
    value = var.record_ttl_millis
  }
}

output "dax_parameter_group_name" {
  description = "The name of the created DAX parameter group."
  value       = aws_dax_parameter_group.custom.name
}

output "dax_parameter_group_id" {
  description = "The ID of the created DAX parameter group."
  value       = aws_dax_parameter_group.custom.id
}