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
  description = "AWS region where the Amazon Connect instance and Lex bot will be created."
  type        = string
  default     = "us-east-1"
}

variable "connect_instance_alias" {
  description = "Alias for the Amazon Connect instance."
  type        = string
  default     = "saml-connect-instance-demo"
}

variable "lex_bot_name" {
  description = "Name of the Amazon Lex V2 bot."
  type        = string
  default     = "connect-demo-lex-v2-bot"
}

resource "aws_iam_role" "lex_bot_role" {
  name = "connect-demo-lex-v2-bot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lexv2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lex_bot_policy" {
  name = "connect-demo-lex-v2-bot-policy"
  role = aws_iam_role.lex_bot_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "polly:SynthesizeSpeech",
          "comprehend:DetectSentiment"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lexv2models_bot" "connect_bot" {
  name                        = var.lex_bot_name
  role_arn                    = aws_iam_role.lex_bot_role.arn
  idle_session_ttl_in_seconds = 300

  data_privacy {
    child_directed = false
  }
}

resource "aws_lexv2models_bot_locale" "en_us" {
  bot_id                           = aws_lexv2models_bot.connect_bot.id
  bot_version                      = "DRAFT"
  locale_id                        = "en_US"
  n_lu_intent_confidence_threshold = 0.40

  voice_settings {
    voice_id = "Joanna"
  }
}

resource "aws_lexv2models_intent" "greeting" {
  bot_id      = aws_lexv2models_bot.connect_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "GreetingIntent"

  sample_utterance {
    utterance = "hello"
  }

  sample_utterance {
    utterance = "hi"
  }

  sample_utterance {
    utterance = "good morning"
  }

  closing_setting {
    closing_response {
      message_group {
        message {
          plain_text_message {
            value = "Hello. This is a demo bot associated with Amazon Connect."
          }
        }
      }
    }
  }

  depends_on = [
    aws_lexv2models_bot_locale.en_us
  ]
}

resource "aws_lexv2models_bot_version" "connect_bot_version" {
  bot_id = aws_lexv2models_bot.connect_bot.id

  locale_specification {
    locale_id = aws_lexv2models_bot_locale.en_us.locale_id

    bot_version_locale_details {
      source_bot_version = "DRAFT"
    }
  }

  depends_on = [
    aws_lexv2models_intent.greeting
  ]
}

resource "aws_lexv2models_bot_alias" "connect_bot_alias" {
  bot_alias_name = "ConnectDemoAlias"
  bot_id         = aws_lexv2models_bot.connect_bot.id
  bot_version    = aws_lexv2models_bot_version.connect_bot_version.bot_version

  bot_alias_locale_settings {
    locale_id = aws_lexv2models_bot_locale.en_us.locale_id
    enabled   = true
  }
}

resource "aws_connect_instance" "saml_instance" {
  identity_management_type = "SAML"
  instance_alias           = var.connect_instance_alias
  inbound_calls_enabled    = true
  outbound_calls_enabled   = true
}

resource "aws_connect_bot_association" "lex_v2_association" {
  instance_id = aws_connect_instance.saml_instance.id

  lex_v2_bot {
    alias_arn = aws_lexv2models_bot_alias.connect_bot_alias.arn
  }
}

output "connect_instance_id" {
  description = "The ID of the Amazon Connect instance."
  value       = aws_connect_instance.saml_instance.id
}

output "connect_instance_arn" {
  description = "The ARN of the Amazon Connect instance."
  value       = aws_connect_instance.saml_instance.arn
}

output "lex_bot_alias_arn" {
  description = "The ARN of the Lex V2 bot alias associated with Amazon Connect."
  value       = aws_lexv2models_bot_alias.connect_bot_alias.arn
}