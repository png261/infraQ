terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

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

  create_version = true
}

resource "aws_lex_bot" "pizza_ordering" {
  name        = "PizzaOrderingBot"
  description = "Lex bot for ordering pizzas."

  child_directed                   = false
  enable_model_improvements       = true
  locale                           = "en-US"
  nlu_intent_confidence_threshold = 0.5
  process_behavior                 = "BUILD"

  abort_statement {
    message {
      content      = "Sorry, I could not understand your pizza order."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "How can I help with your pizza order?"
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = aws_lex_intent.order_pizza.version
  }
}
