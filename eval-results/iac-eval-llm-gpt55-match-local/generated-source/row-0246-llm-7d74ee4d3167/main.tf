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

resource "aws_chime_voice_connector" "primary" {
  name               = "primary-encrypted-voice-connector"
  aws_region         = "us-east-1"
  require_encryption = true

  tags = {
    Name        = "primary-encrypted-voice-connector"
    Environment = "example"
  }
}

resource "aws_chime_voice_connector" "secondary" {
  name               = "secondary-encrypted-voice-connector"
  aws_region         = "us-east-1"
  require_encryption = true

  tags = {
    Name        = "secondary-encrypted-voice-connector"
    Environment = "example"
  }
}

resource "aws_chime_voice_connector_group" "encrypted_group" {
  name = "encrypted-voice-connector-group"

  connector {
    voice_connector_id = aws_chime_voice_connector.primary.id
    priority           = 1
  }

  connector {
    voice_connector_id = aws_chime_voice_connector.secondary.id
    priority           = 2
  }

  tags = {
    Name        = "encrypted-voice-connector-group"
    Environment = "example"
  }
}

output "primary_voice_connector_id" {
  value = aws_chime_voice_connector.primary.id
}

output "secondary_voice_connector_id" {
  value = aws_chime_voice_connector.secondary.id
}

output "voice_connector_group_id" {
  value = aws_chime_voice_connector_group.encrypted_group.id
}