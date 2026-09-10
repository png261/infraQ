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
  description = "AWS region for deploying the Chime Voice Connector."
  type        = string
  default     = "us-east-1"
}

variable "voice_connector_name" {
  description = "Name of the AWS Chime Voice Connector."
  type        = string
  default     = "encrypted-chime-voice-connector"
}

resource "aws_chime_voice_connector" "this" {
  name               = var.voice_connector_name
  require_encryption = true

  tags = {
    Name        = var.voice_connector_name
    Environment = "example"
    ManagedBy   = "terraform"
  }
}

resource "aws_chime_voice_connector_streaming" "this" {
  voice_connector_id = aws_chime_voice_connector.this.id

  data_retention_in_hours = 5

  /*
    Disables media streaming to Amazon Kinesis Video Streams.
    The streaming configuration remains present, with SNS notifications enabled.
  */
  disabled = true

  streaming_notification_targets = [
    "SNS"
  ]
}

output "voice_connector_id" {
  description = "ID of the AWS Chime Voice Connector."
  value       = aws_chime_voice_connector.this.id
}

output "voice_connector_name" {
  description = "Name of the AWS Chime Voice Connector."
  value       = aws_chime_voice_connector.this.name
}

output "streaming_retention_hours" {
  description = "Configured streaming retention period in hours."
  value       = aws_chime_voice_connector_streaming.this.data_retention_in_hours
}

output "streaming_notifications" {
  description = "Configured streaming notification targets."
  value       = aws_chime_voice_connector_streaming.this.streaming_notification_targets
}