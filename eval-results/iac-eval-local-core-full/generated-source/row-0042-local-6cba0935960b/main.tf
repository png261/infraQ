resource "aws_lex_intent" "example" {
  name = "example_intent"

  sample_utterances = [
    "hello",
    "help me",
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_bot" "example" {
  name        = "example_bot"
  description = "Minimal example Amazon Lex bot."

  child_directed  = false
  locale          = "en-US"
  process_behavior = "BUILD"
  voice_id        = "Joanna"

  abort_statement {
    message {
      content      = "Sorry, I could not understand. Goodbye."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "I did not understand. Can you repeat that?"
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.example.name
    intent_version = aws_lex_intent.example.version
  }
}
