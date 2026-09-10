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

resource "aws_chime_voice_connector" "primary" {
  name               = "iac-eval-primary"
  require_encryption = true
}

resource "aws_chime_voice_connector" "secondary" {
  name               = "iac-eval-secondary"
  require_encryption = true
}

resource "aws_chime_voice_connector_group" "this" {
  name = "iac-eval-voice-connector-group"

  connector {
    voice_connector_id = aws_chime_voice_connector.primary.id
    priority           = 1
  }

  connector {
    voice_connector_id = aws_chime_voice_connector.secondary.id
    priority           = 2
  }
}
