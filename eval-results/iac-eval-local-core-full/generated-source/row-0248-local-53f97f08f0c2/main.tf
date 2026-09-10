terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0, < 6.0.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_chime_voice_connector" "primary" {
  name               = "benchmark-primary-voice-connector"
  require_encryption = true
}

resource "aws_chime_voice_connector" "secondary" {
  name               = "benchmark-secondary-voice-connector"
  require_encryption = true
}

resource "aws_chime_voice_connector_group" "benchmark" {
  name = "benchmark-voice-connector-group"

  connector {
    voice_connector_id = aws_chime_voice_connector.primary.id
    priority           = 1
  }

  connector {
    voice_connector_id = aws_chime_voice_connector.secondary.id
    priority           = 3
  }
}
