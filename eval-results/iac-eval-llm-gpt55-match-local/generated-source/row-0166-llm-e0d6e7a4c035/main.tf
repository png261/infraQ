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
  region = "us-east-1"
}

resource "aws_dynamodb_table" "example" {
  name         = "example-dynamodb-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = "example-dynamodb-table"
    Environment = "dev"
  }
}

resource "aws_dynamodb_table_item" "example_item" {
  table_name = aws_dynamodb_table.example.name
  hash_key   = aws_dynamodb_table.example.hash_key

  item = jsonencode({
    id = {
      S = "item-001"
    }
    name = {
      S = "Example Item"
    }
    description = {
      S = "This is an example DynamoDB table item created with Terraform."
    }
    active = {
      BOOL = true
    }
    count = {
      N = "1"
    }
  })
}