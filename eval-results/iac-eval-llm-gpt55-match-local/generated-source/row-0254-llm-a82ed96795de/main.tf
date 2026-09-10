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

variable "voice_connector_name" {
  description = "Name of the AWS Chime SDK Voice Connector."
  type        = string
  default     = "example-chime-voice-connector"
}

variable "kinesis_video_stream_name" {
  description = "Name of the Amazon Kinesis Video Stream for media streaming."
  type        = string
  default     = "example-chime-media-stream"
}

variable "media_retention_hours" {
  description = "Retention period in hours for the Kinesis Video Stream."
  type        = number
  default     = 24
}

variable "voice_connector_stream_retention_days" {
  description = "Retention period in days for Chime Voice Connector media streaming."
  type        = number
  default     = 1
}

resource "aws_kinesis_video_stream" "chime_media_stream" {
  name                    = var.kinesis_video_stream_name
  data_retention_in_hours = var.media_retention_hours
  media_type              = "audio/L16"

  tags = {
    Name        = var.kinesis_video_stream_name
    Environment = "example"
    ManagedBy   = "terraform"
  }
}

resource "aws_chimesdkvoice_voice_connector" "this" {
  name               = var.voice_connector_name
  require_encryption = true
  aws_region         = var.aws_region

  tags = {
    Name        = var.voice_connector_name
    Environment = "example"
    ManagedBy   = "terraform"
  }
}

resource "aws_chimesdkvoice_voice_connector_streaming" "this" {
  voice_connector_id = aws_chimesdkvoice_voice_connector.this.id

  data_retention = var.voice_connector_stream_retention_days
  disabled       = false

  streaming_notification_targets = [
    "EventBridge"
  ]
}

output "voice_connector_id" {
  description = "ID of the AWS Chime SDK Voice Connector."
  value       = aws_chimesdkvoice_voice_connector.this.id
}

output "voice_connector_arn" {
  description = "ARN of the AWS Chime SDK Voice Connector."
  value       = aws_chimesdkvoice_voice_connector.this.arn
}

output "kinesis_video_stream_name" {
  description = "Name of the Kinesis Video Stream."
  value       = aws_kinesis_video_stream.chime_media_stream.name
}

output "kinesis_video_stream_arn" {
  description = "ARN of the Kinesis Video Stream."
  value       = aws_kinesis_video_stream.chime_media_stream.arn
}