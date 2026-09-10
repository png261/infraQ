terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "primary_region" {
  description = "Primary AWS region for the DynamoDB Global Table."
  type        = string
  default     = "us-east-1"
}

variable "replica_region" {
  description = "Replica AWS region for the DynamoDB Global Table."
  type        = string
  default     = "us-west-2"
}

variable "table_name" {
  description = "Name of the DynamoDB Global Table."
  type        = string
  default     = "example-global-table"
}

provider "aws" {
  region = var.primary_region
}

provider "aws" {
  alias  = "replica"
  region = var.replica_region
}

resource "aws_dynamodb_table" "global_table" {
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

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery {
    enabled = true
  }

  replica {
    region_name = var.replica_region

    point_in_time_recovery = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = var.table_name
    Environment = "example"
    ManagedBy   = "terraform"
  }
}

output "global_table_name" {
  description = "Name of the DynamoDB Global Table."
  value       = aws_dynamodb_table.global_table.name
}

output "global_table_arn" {
  description = "ARN of the primary DynamoDB table."
  value       = aws_dynamodb_table.global_table.arn
}

output "primary_region" {
  description = "Primary region of the DynamoDB Global Table."
  value       = var.primary_region
}

output "replica_region" {
  description = "Replica region of the DynamoDB Global Table."
  value       = var.replica_region
}