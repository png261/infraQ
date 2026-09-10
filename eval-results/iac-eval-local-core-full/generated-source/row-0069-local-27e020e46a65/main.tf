terraform {
  required_version = ">= 1.5.0"

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

resource "aws_kinesis_stream" "example" {
  name        = "iac-eval-example-stream"
  shard_count = 1

  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
}

resource "aws_kinesis_stream_consumer" "example" {
  name       = "iac-eval-example-consumer"
  stream_arn = aws_kinesis_stream.example.arn
}
