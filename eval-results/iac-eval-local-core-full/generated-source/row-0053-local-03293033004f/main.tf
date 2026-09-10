data "aws_region" "current" {}

resource "aws_connect_instance" "example" {
  identity_management_type = "CONNECT_MANAGED"
  inbound_calls_enabled    = true
  outbound_calls_enabled   = true
  instance_alias           = "iac-eval-connect-bot-association"
}

resource "aws_lex_intent" "example" {
  name = "IacEvalExampleIntent"

  sample_utterances = [
    "help",
    "I need help",
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_bot" "example" {
  name        = "IacEvalExampleBot"
  description = "Minimal Lex bot for an Amazon Connect bot association benchmark."

  child_directed = false
  locale         = "en-US"

  abort_statement {
    message {
      content      = "Sorry, I cannot help with that request."
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
    intent_name    = aws_lex_intent.example.name
    intent_version = aws_lex_intent.example.version
  }
}

resource "aws_connect_bot_association" "example" {
  instance_id = aws_connect_instance.example.id

  lex_bot {
    name       = aws_lex_bot.example.name
    lex_region = data.aws_region.current.name
  }
}
