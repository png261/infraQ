resource "aws_lex_intent" "order_pizza" {
  name        = "OrderPizza"
  description = "Intent for helping a child order a pizza."

  sample_utterances = [
    "I want a pizza",
    "Can I order pizza",
    "Please order a cheese pizza",
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_bot" "kids_pizza_ordering" {
  name        = "KidsPizzaOrderingBot"
  description = "A child-directed bot for ordering pizzas."

  child_directed   = true
  locale           = "en-US"
  process_behavior = "BUILD"

  abort_statement {
    message {
      content      = "Sorry, I could not help with that pizza order."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "What kind of pizza would you like?"
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = aws_lex_intent.order_pizza.version
  }
}
