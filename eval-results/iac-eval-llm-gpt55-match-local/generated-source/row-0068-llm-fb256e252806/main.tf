terraform {
  required_version = ">= 1.0.0"

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
  description = "AWS region where the Kinesis Video Stream will be created."
  type        = string
  default     = "us-east-1"
}

variable "stream_name" {
  description = "Name of the Kinesis Video Stream."
  type        = string
  default     = "basic-kinesis-video-stream"
}

resource "aws_kinesis_video_stream" "basic" {
  name                    = var.stream_name
  data_retention_in_hours = 24
  device_name             = "basic-video-device"
  media_type              = "video/h264"

  tags = {
    Name        = var.stream_name
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

output "kinesis_video_stream_name" {
  description = "The name of the Kinesis Video Stream."
  value       = aws_kinesis_video_stream.basic.name
}

output "kinesis_video_stream_arn" {
  description = "The ARN of the Kinesis Video Stream."
  value       = aws_kinesis_video_stream.basic.arn
}