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

variable "voice_connector_name" {
  description = "Name of the AWS Chime SDK Voice Connector."
  type        = string
  default     = "encrypted-media-metrics-voice-connector"
}

variable "voice_connector_region" {
  description = "AWS region for the Chime SDK Voice Connector."
  type        = string
  default     = "us-east-1"
}

resource "aws_chimesdkvoice_voice_connector" "this" {
  name               = var.voice_connector_name
  require_encryption = true
  aws_region         = var.voice_connector_region

  tags = {
    Name        = var.voice_connector_name
    Environment = "example"
    ManagedBy   = "terraform"
  }
}

resource "aws_chimesdkvoice_voice_connector_logging" "this" {
  voice_connector_id = aws_chimesdkvoice_voice_connector.this.id

  logging_configuration {
    enable_sip_logs           = true
    enable_media_metric_logs  = true
  }
}

output "voice_connector_id" {
  description = "ID of the AWS Chime SDK Voice Connector."
  value       = aws_chimesdkvoice_voice_connector.this.id
}

output "voice_connector_name" {
  description = "Name of the AWS Chime SDK Voice Connector."
  value       = aws_chimesdkvoice_voice_connector.this.name
}

output "voice_connector_region" {
  description = "Region of the AWS Chime SDK Voice Connector."
  value       = aws_chimesdkvoice_voice_connector.this.aws_region
}