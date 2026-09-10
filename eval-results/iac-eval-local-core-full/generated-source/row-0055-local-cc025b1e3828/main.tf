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

data "aws_region" "current" {}

resource "aws_connect_instance" "saml" {
  identity_management_type = "SAML"
  inbound_calls_enabled    = true
  outbound_calls_enabled   = true
  instance_alias           = "iac-eval-saml-connect"
}

resource "aws_lex_intent" "help" {
  name = "IacEvalHelpIntent"

  sample_utterances = [
    "help",
    "I need help",
    "connect me to support"
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_bot" "support" {
  name        = "IacEvalSupportBot"
  description = "Minimal Lex bot for Amazon Connect association benchmark."

  child_directed = false
  locale         = "en-US"

  abort_statement {
    message {
      content      = "Sorry, I could not help with that request."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "How can I help you?"
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.help.name
    intent_version = aws_lex_intent.help.version
  }

  process_behavior = "BUILD"
}

resource "aws_connect_bot_association" "lex" {
  instance_id = aws_connect_instance.saml.id

  lex_bot {
    name       = aws_lex_bot.support.name
    lex_region = data.aws_region.current.name
  }
}
