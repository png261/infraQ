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
  description = "AWS region where the DynamoDB table and Contributor Insights resource will be created."
  type        = string
  default     = "us-east-1"
}

variable "table_name" {
  description = "Name of the DynamoDB table for which Contributor Insights will be enabled."
  type        = string
  default     = "custom-contributor-insights-table"
}

variable "contributor_insights_enabled" {
  description = "Whether DynamoDB Contributor Insights should be enabled for the table."
  type        = bool
  default     = true
}

variable "environment" {
  description = "Deployment environment tag."
  type        = string
  default     = "dev"
}

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "pk"
  range_key = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  deletion_protection_enabled = false

  tags = {
    Name        = var.table_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Feature     = "DynamoDBContributorInsights"
  }
}

resource "aws_dynamodb_contributor_insights" "this" {
  table_name = aws_dynamodb_table.this.name
  enabled    = var.contributor_insights_enabled
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  value       = aws_dynamodb_table.this.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table."
  value       = aws_dynamodb_table.this.arn
}

output "contributor_insights_enabled" {
  description = "Whether Contributor Insights is enabled for the DynamoDB table."
  value       = aws_dynamodb_contributor_insights.this.enabled
}