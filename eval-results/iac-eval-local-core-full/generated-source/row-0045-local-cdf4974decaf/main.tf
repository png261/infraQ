resource "aws_lex_intent" "order_pizza" {
  name = "OrderPizza"

  sample_utterances = [
    "I want to order a pizza",
    "Order a pizza",
    "Can I get a pizza",
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_bot" "pizza_ordering" {
  name        = "PizzaOrderingBot"
  description = "A minimal Amazon Lex bot for ordering pizzas."

  child_directed = false
  locale         = "en-US"

  abort_statement {
    message {
      content      = "Sorry, I could not complete your pizza order."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "I can help you order a pizza. What would you like?"
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = aws_lex_intent.order_pizza.version
  }

  process_behavior = "BUILD"

  conclusion_statement {
    message {
      content      = "Thanks, your pizza order request has been recorded."
      content_type = "PlainText"
    }
  }
}
