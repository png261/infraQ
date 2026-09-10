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

variable "connect_instance_alias" {
  description = "Alias for the Amazon Connect instance."
  type        = string
  default     = "kids-connect-instance"
}

variable "lex_bot_name" {
  description = "Name of the Amazon Lex bot."
  type        = string
  default     = "KidsHelperBot"
}

resource "aws_connect_instance" "kids" {
  identity_management_type = "CONNECT_MANAGED"
  inbound_calls_enabled    = true
  outbound_calls_enabled   = true

  instance_alias = var.connect_instance_alias
}

resource "aws_lex_intent" "kids_help" {
  name = "KidsHelpIntent"

  description = "Intent for helping kids with simple requests."

  sample_utterances = [
    "I need help",
    "Can you help me",
    "I have a question",
    "Help me please"
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_bot" "kids" {
  name        = var.lex_bot_name
  description = "A simple Amazon Lex bot intended for kid-friendly help interactions."

  child_directed = true
  locale         = "en-US"

  process_behavior = "BUILD"

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "Sorry, I did not understand. Can you say that again?"
      content_type = "PlainText"
    }
  }

  abort_statement {
    message {
      content      = "Sorry, I am not able to help with that right now."
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.kids_help.name
    intent_version = "$LATEST"
  }

  depends_on = [
    aws_lex_intent.kids_help
  ]
}

resource "aws_connect_bot_association" "kids" {
  instance_id = aws_connect_instance.kids.id

  lex_bot {
    name       = aws_lex_bot.kids.name
    lex_region = var.aws_region
  }

  depends_on = [
    aws_connect_instance.kids,
    aws_lex_bot.kids
  ]
}