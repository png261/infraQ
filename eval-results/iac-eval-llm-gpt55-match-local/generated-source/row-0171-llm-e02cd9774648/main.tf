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
  default     = "on-demand-dynamodb-table"
}

resource "aws_dynamodb_table" "on_demand_table" {
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

  server_side_encryption {
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
  value       = aws_dynamodb_table.on_demand_table.name
}

output "dynamodb_table_arn" {
  description = "The ARN of the DynamoDB table."
  value       = aws_dynamodb_table.on_demand_table.arn
}

output "dynamodb_billing_mode" {
  description = "The billing mode configured for the DynamoDB table."
  value       = aws_dynamodb_table.on_demand_table.billing_mode
}