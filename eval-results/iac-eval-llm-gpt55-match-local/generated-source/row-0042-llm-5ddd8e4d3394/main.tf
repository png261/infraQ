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
  description = "AWS region where the Lex bot will be created."
  type        = string
  default     = "us-east-1"
}

variable "lex_bot_name" {
  description = "Name of the AWS Lex bot."
  type        = string
  default     = "SampleTerraformLexBot"
}

variable "lex_intent_name" {
  description = "Name of the AWS Lex intent."
  type        = string
  default     = "SampleGreetingIntent"
}

resource "aws_lex_intent" "greeting_intent" {
  name        = var.lex_intent_name
  description = "A simple greeting intent created by Terraform."

  sample_utterances = [
    "hello",
    "hi",
    "hey",
    "good morning",
    "good afternoon",
    "good evening"
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }

  conclusion_statement {
    message {
      content_type = "PlainText"
      content      = "Hello! How can I help you today?"
    }

    response_card = "GreetingResponseCard"
  }

  create_version = false
}

resource "aws_lex_bot" "this" {
  name        = var.lex_bot_name
  description = "A basic AWS Lex bot created using Terraform."

  locale                     = "en-US"
  child_directed             = false
  idle_session_ttl_in_seconds = 300
  process_behavior           = "BUILD"

  clarification_prompt {
    max_attempts = 2

    message {
      content_type = "PlainText"
      content      = "I did not understand that. Can you please rephrase?"
    }
  }

  abort_statement {
    message {
      content_type = "PlainText"
      content      = "Sorry, I am unable to help with that request right now."
    }
  }

  intent {
    intent_name    = aws_lex_intent.greeting_intent.name
    intent_version = "$LATEST"
  }

  voice_id = "Joanna"

  create_version = false

  depends_on = [
    aws_lex_intent.greeting_intent
  ]
}

output "lex_bot_name" {
  description = "The name of the created AWS Lex bot."
  value       = aws_lex_bot.this.name
}

output "lex_bot_arn" {
  description = "The ARN of the created AWS Lex bot."
  value       = aws_lex_bot.this.arn
}

output "lex_intent_name" {
  description = "The name of the created AWS Lex intent."
  value       = aws_lex_intent.greeting_intent.name
}