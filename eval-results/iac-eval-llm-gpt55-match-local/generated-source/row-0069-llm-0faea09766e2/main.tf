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

variable "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream."
  type        = string
  default     = "example-kinesis-stream"
}

variable "kinesis_consumer_name" {
  description = "Name of the Kinesis Stream Consumer."
  type        = string
  default     = "example-kinesis-consumer"
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
    ManagedBy   = "terraform"
  }
}

resource "aws_kinesis_stream_consumer" "example" {
  name       = var.kinesis_consumer_name
  stream_arn = aws_kinesis_stream.example.arn
}

output "kinesis_stream_name" {
  description = "Name of the created Kinesis Data Stream."
  value       = aws_kinesis_stream.example.name
}

output "kinesis_stream_arn" {
  description = "ARN of the created Kinesis Data Stream."
  value       = aws_kinesis_stream.example.arn
}

output "kinesis_stream_consumer_name" {
  description = "Name of the Kinesis Stream Consumer."
  value       = aws_kinesis_stream_consumer.example.name
}

output "kinesis_stream_consumer_arn" {
  description = "ARN of the Kinesis Stream Consumer."
  value       = aws_kinesis_stream_consumer.example.arn
}