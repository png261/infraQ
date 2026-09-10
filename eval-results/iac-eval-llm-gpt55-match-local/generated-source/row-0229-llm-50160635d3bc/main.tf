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
  description = "AWS region where the DynamoDB table will be created."
  type        = string
  default     = "us-east-1"
}

variable "table_name" {
  description = "Name of the DynamoDB table."
  type        = string
  default     = "pitr-enabled-dynamodb-table"
}

resource "aws_dynamodb_table" "example" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = var.table_name
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table."
  value       = aws_dynamodb_table.example.name
}

output "point_in_time_recovery_enabled" {
  description = "Whether point-in-time recovery is enabled for the DynamoDB table."
  value       = aws_dynamodb_table.example.point_in_time_recovery[0].enabled
}