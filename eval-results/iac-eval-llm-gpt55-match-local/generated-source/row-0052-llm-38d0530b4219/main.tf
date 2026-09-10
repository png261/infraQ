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
  region = "us-east-1"
}

resource "aws_iam_role" "lex_bot_role" {
  name = "children-lexv2-bot-role"

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
  name = "children-lexv2-bot-policy"
  role = aws_iam_role.lex_bot_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "polly:SynthesizeSpeech",
          "comprehend:DetectSentiment",
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lexv2models_bot" "children_bot" {
  name                        = "children-friendly-bot"
  description                 = "A child-directed AWS Lex V2 bot with simple and friendly interactions."
  role_arn                    = aws_iam_role.lex_bot_role.arn
  idle_session_ttl_in_seconds = 300

  data_privacy {
    child_directed = true
  }
}

resource "aws_lexv2models_bot_locale" "children_bot_en_us" {
  bot_id                           = aws_lexv2models_bot.children_bot.id
  bot_version                      = "DRAFT"
  locale_id                        = "en_US"
  description                      = "English US locale for the child-friendly Lex bot."
  n_lu_intent_confidence_threshold = 0.40

  voice_settings {
    voice_id = "Joanna"
  }
}

resource "aws_lexv2models_intent" "say_hello" {
  bot_id      = aws_lexv2models_bot.children_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.children_bot_en_us.locale_id

  name        = "SayHello"
  description = "A simple greeting intent for children."

  sample_utterance {
    utterance = "hello"
  }

  sample_utterance {
    utterance = "hi"
  }

  sample_utterance {
    utterance = "hey there"
  }

  sample_utterance {
    utterance = "good morning"
  }

  sample_utterance {
    utterance = "can you say hi"
  }

  closing_response {
    message_group {
      message {
        plain_text_message {
          value = "Hi there! I am your friendly helper bot. What would you like to talk about today?"
        }
      }
    }
  }

  depends_on = [
    aws_lexv2models_bot_locale.children_bot_en_us
  ]
}

resource "aws_lexv2models_intent" "fallback" {
  bot_id      = aws_lexv2models_bot.children_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.children_bot_en_us.locale_id

  name                    = "FallbackIntent"
  description             = "Fallback intent for unrecognized child-friendly requests."
  parent_intent_signature = "AMAZON.FallbackIntent"

  closing_response {
    message_group {
      message {
        plain_text_message {
          value = "I'm sorry, I didn't understand that. Could you try asking in another way?"
        }
      }
    }
  }

  depends_on = [
    aws_lexv2models_bot_locale.children_bot_en_us
  ]
}

output "lexv2_bot_id" {
  description = "The ID of the AWS Lex V2 bot."
  value       = aws_lexv2models_bot.children_bot.id
}

output "lexv2_bot_name" {
  description = "The name of the AWS Lex V2 bot."
  value       = aws_lexv2models_bot.children_bot.name
}

output "lexv2_bot_locale" {
  description = "The locale configured for the AWS Lex V2 bot."
  value       = aws_lexv2models_bot_locale.children_bot_en_us.locale_id
}