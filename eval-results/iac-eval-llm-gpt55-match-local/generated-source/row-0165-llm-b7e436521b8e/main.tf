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

resource "aws_dynamodb_table" "custom_capacity_table" {
  name           = "custom-capacity-dynamodb-table"
  billing_mode   = "PROVISIONED"
  read_capacity  = 20
  write_capacity = 20

  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = "custom-capacity-dynamodb-table"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}