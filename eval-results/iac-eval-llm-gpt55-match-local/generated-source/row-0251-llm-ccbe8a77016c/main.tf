terraform {
  required_version = ">= 1.3.0"

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
  description = "AWS region used by the Terraform AWS provider."
  type        = string
  default     = "us-east-1"
}

variable "voice_connector_name" {
  description = "Name of the AWS Chime Voice Connector."
  type        = string
  default     = "example-chime-voice-connector"
}

variable "voice_connector_region" {
  description = "AWS region for the Chime Voice Connector."
  type        = string
  default     = "us-east-1"
}

resource "aws_chime_voice_connector" "this" {
  name               = var.voice_connector_name
  aws_region         = var.voice_connector_region
  require_encryption = true
}

resource "aws_chime_voice_connector_logging" "this" {
  voice_connector_id = aws_chime_voice_connector.this.id

  logging_configuration {
    enable_sip_logs          = false
    enable_media_metric_logs = true
  }
}