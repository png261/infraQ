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
  default     = "custom-ttl-demo-table"
}

variable "ttl_attribute_name" {
  description = "Custom DynamoDB TTL attribute name. Items expire when this attribute contains a Unix epoch timestamp in seconds."
  type        = string
  default     = "expires_at"
}

resource "aws_dynamodb_table" "ttl_table" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }

  ttl {
    attribute_name = var.ttl_attribute_name
    enabled        = true
  }

  tags = {
    Name        = var.table_name
    Environment = "demo"
    ManagedBy   = "Terraform"
  }
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  value       = aws_dynamodb_table.ttl_table.name
}

output "ttl_attribute_name" {
  description = "Custom TTL attribute configured for item expiration."
  value       = aws_dynamodb_table.ttl_table.ttl[0].attribute_name
}

output "ttl_enabled" {
  description = "Whether TTL is enabled on the DynamoDB table."
  value       = aws_dynamodb_table.ttl_table.ttl[0].enabled
}