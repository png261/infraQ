terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the Amazon Connect instance and Lex bot will be created."
  type        = string
  default     = "us-east-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_connect_instance" "this" {
  instance_alias           = "connect-bot-${random_id.suffix.hex}"
  identity_management_type = "CONNECT_MANAGED"

  inbound_calls_enabled  = true
  outbound_calls_enabled = true
}

resource "aws_lex_intent" "this" {
  name        = "ConnectDemoIntent${random_id.suffix.hex}"
  description = "Demo Lex intent for Amazon Connect bot association."

  sample_utterances = [
    "hello",
    "help",
    "I need assistance"
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_bot" "this" {
  name        = "ConnectDemoBot${random_id.suffix.hex}"
  description = "Demo Lex bot associated with Amazon Connect."

  locale                        = "en-US"
  child_directed                = false
  idle_session_ttl_in_seconds   = 300
  process_behavior              = "BUILD"
  detect_sentiment              = false
  create_version                = false

  abort_statement {
    message {
      content      = "Sorry, I am unable to help with that request."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "Can you please repeat that?"
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.this.name
    intent_version = "$LATEST"
  }

  depends_on = [
    aws_lex_intent.this
  ]
}

resource "aws_connect_bot_association" "this" {
  instance_id = aws_connect_instance.this.id

  lex_bot {
    name       = aws_lex_bot.this.name
    lex_region = var.aws_region
  }

  depends_on = [
    aws_lex_bot.this
  ]
}

output "connect_instance_id" {
  description = "The ID of the Amazon Connect instance."
  value       = aws_connect_instance.this.id
}

output "lex_bot_name" {
  description = "The name of the Lex bot associated with Amazon Connect."
  value       = aws_lex_bot.this.name
}

output "connect_bot_association_id" {
  description = "The ID of the Amazon Connect bot association."
  value       = aws_connect_bot_association.this.id
}