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
  description = "AWS region where the Kinesis stream will be created."
  type        = string
  default     = "us-east-1"
}

variable "stream_name" {
  description = "Name of the Amazon Kinesis Data Stream."
  type        = string
  default     = "basic-kinesis-stream"
}

variable "shard_count" {
  description = "Number of shards for the Kinesis stream."
  type        = number
  default     = 1
}

variable "retention_period" {
  description = "Retention period for records in the stream, in hours."
  type        = number
  default     = 24
}

resource "aws_kinesis_stream" "basic_stream" {
  name             = var.stream_name
  shard_count      = var.shard_count
  retention_period = var.retention_period

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = {
    Name        = var.stream_name
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

output "kinesis_stream_name" {
  description = "Name of the created Kinesis stream."
  value       = aws_kinesis_stream.basic_stream.name
}

output "kinesis_stream_arn" {
  description = "ARN of the created Kinesis stream."
  value       = aws_kinesis_stream.basic_stream.arn
}