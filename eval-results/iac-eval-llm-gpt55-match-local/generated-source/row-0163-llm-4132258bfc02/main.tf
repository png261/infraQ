terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "table_name" {
  description = "Name of the DynamoDB table to create in each region."
  type        = string
  default     = "multi-region-dynamodb-table"
}

provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "usw1"
  region = "us-west-1"
}

provider "aws" {
  alias  = "usw2"
  region = "us-west-2"
}

resource "aws_dynamodb_table" "us_east_1" {
  provider = aws.use1

  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = var.table_name
    Environment = "default"
    Region      = "us-east-1"
    ManagedBy   = "Terraform"
  }
}

resource "aws_dynamodb_table" "us_west_1" {
  provider = aws.usw1

  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = var.table_name
    Environment = "default"
    Region      = "us-west-1"
    ManagedBy   = "Terraform"
  }
}

resource "aws_dynamodb_table" "us_west_2" {
  provider = aws.usw2

  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = var.table_name
    Environment = "default"
    Region      = "us-west-2"
    ManagedBy   = "Terraform"
  }
}

output "dynamodb_table_us_east_1_name" {
  description = "Name of the DynamoDB table in us-east-1."
  value       = aws_dynamodb_table.us_east_1.name
}

output "dynamodb_table_us_west_1_name" {
  description = "Name of the DynamoDB table in us-west-1."
  value       = aws_dynamodb_table.us_west_1.name
}

output "dynamodb_table_us_west_2_name" {
  description = "Name of the DynamoDB table in us-west-2."
  value       = aws_dynamodb_table.us_west_2.name
}

output "dynamodb_table_us_east_1_arn" {
  description = "ARN of the DynamoDB table in us-east-1."
  value       = aws_dynamodb_table.us_east_1.arn
}

output "dynamodb_table_us_west_1_arn" {
  description = "ARN of the DynamoDB table in us-west-1."
  value       = aws_dynamodb_table.us_west_1.arn
}

output "dynamodb_table_us_west_2_arn" {
  description = "ARN of the DynamoDB table in us-west-2."
  value       = aws_dynamodb_table.us_west_2.arn
}