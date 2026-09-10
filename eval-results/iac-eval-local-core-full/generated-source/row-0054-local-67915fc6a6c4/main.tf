resource "aws_connect_instance" "kids" {
  identity_management_type = "CONNECT_MANAGED"
  inbound_calls_enabled    = true
  outbound_calls_enabled   = true
  instance_alias           = "kids-connect-instance"
}

resource "aws_lex_intent" "kids_help" {
  name            = "KidsHelpIntent"
  create_version  = false
  sample_utterances = [
    "I need help",
    "Can you help me",
    "I have a question"
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_bot" "kids" {
  name        = "KidsHelpBot"
  description = "A child-directed Lex bot for kids help routing in ${data.aws_region.current.name}."

  child_directed              = true
  idle_session_ttl_in_seconds = 300
  locale                      = "en-US"
  process_behavior            = "BUILD"

  abort_statement {
    message {
      content      = "Sorry, I cannot help with that right now."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "How can I help you today?"
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.kids_help.name
    intent_version = "$LATEST"
  }
}

resource "aws_connect_bot_association" "kids" {
  instance_id = aws_connect_instance.kids.id
  lex_bot {
    name       = aws_lex_bot.kids.name
    lex_region = data.aws_region.current.name
  }
}
