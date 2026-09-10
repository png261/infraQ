terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_dynamodb_table" "example" {
  name           = "example-dynamodb-table"
  billing_mode   = "PROVISIONED"
  read_capacity  = 10
  write_capacity = 10

  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = "example-dynamodb-table"
    Environment = "dev"
  }
}