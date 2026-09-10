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
  region = var.primary_region
}

variable "primary_region" {
  description = "Primary AWS region where the DynamoDB table is created."
  type        = string
  default     = "us-east-1"
}

variable "table_name" {
  description = "Name of the DynamoDB global table."
  type        = string
  default     = "example-global-dynamodb-table"
}

resource "aws_dynamodb_table" "global_table" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "id"
    type = "S"
  }

  replica {
    region_name = "us-east-2"
  }

  replica {
    region_name = "us-west-2"
  }

  tags = {
    Name        = var.table_name
    Environment = "example"
    ManagedBy   = "Terraform"
  }
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB global table."
  value       = aws_dynamodb_table.global_table.name
}

output "dynamodb_table_arn" {
  description = "ARN of the primary DynamoDB table."
  value       = aws_dynamodb_table.global_table.arn
}

output "replica_regions" {
  description = "Regions where DynamoDB replicas are created."
  value = [
    "us-east-2",
    "us-west-2"
  ]
}