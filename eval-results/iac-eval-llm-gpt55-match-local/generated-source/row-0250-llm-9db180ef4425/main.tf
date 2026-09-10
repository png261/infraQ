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

resource "aws_chime_voice_connector" "this" {
  name               = "example-chime-voice-connector"
  require_encryption = true
  aws_region         = "us-east-1"
}

resource "aws_chime_voice_connector_logging" "this" {
  voice_connector_id        = aws_chime_voice_connector.this.id
  enable_sip_logs           = false
  enable_media_metric_logs  = true
}