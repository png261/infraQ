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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  type        = string
  default     = "example-kinesis-destination-table"
}

variable "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream."
  type        = string
  default     = "example-dynamodb-kinesis-stream"
}

resource "aws_dynamodb_table" "example" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = var.dynamodb_table_name
    Environment = "example"
  }
}

resource "aws_kinesis_stream" "example" {
  name             = var.kinesis_stream_name
  shard_count      = 1
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = {
    Name        = var.kinesis_stream_name
    Environment = "example"
  }
}

resource "aws_dynamodb_kinesis_streaming_destination" "example" {
  table_name = aws_dynamodb_table.example.name
  stream_arn = aws_kinesis_stream.example.arn

  depends_on = [
    aws_dynamodb_table.example,
    aws_kinesis_stream.example
  ]
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table."
  value       = aws_dynamodb_table.example.name
}

output "kinesis_stream_name" {
  description = "The name of the Kinesis stream."
  value       = aws_kinesis_stream.example.name
}

output "kinesis_stream_arn" {
  description = "The ARN of the Kinesis stream."
  value       = aws_kinesis_stream.example.arn
}

output "dynamodb_kinesis_streaming_destination_id" {
  description = "The ID of the DynamoDB Kinesis Streaming Destination."
  value       = aws_dynamodb_kinesis_streaming_destination.example.id
}