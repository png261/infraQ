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

resource "aws_lex_slot_type" "pizza_size" {
  name                     = "PizzaSize"
  description              = "Pizza sizes that can be ordered."
  create_version           = true
  value_selection_strategy = "ORIGINAL_VALUE"

  enumeration_value {
    value = "small"
  }

  enumeration_value {
    value = "medium"
  }

  enumeration_value {
    value = "large"
  }
}

resource "aws_lex_intent" "order_pizza" {
  name           = "OrderPizza"
  description    = "Collects information needed to order a pizza."
  create_version = true

  sample_utterances = [
    "I want to order a pizza",
    "Order a pizza",
    "Can I get a pizza",
  ]

  slot {
    name           = "PizzaSize"
    description    = "The requested pizza size."
    priority       = 1
    slot_constraint = "Required"
    slot_type      = aws_lex_slot_type.pizza_size.name
    slot_type_version = aws_lex_slot_type.pizza_size.version

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What size pizza would you like: small, medium, or large?"
        content_type = "PlainText"
      }
    }
  }

  follow_up_prompt {
    prompt {
      max_attempts = 2

      message {
        content      = "Would you like to add another pizza to your order?"
        content_type = "PlainText"
      }
    }

    rejection_statement {
      message {
        content      = "Okay, I will continue with your current pizza order."
        content_type = "PlainText"
      }
    }
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_bot" "pizza_order" {
  name        = "PizzaOrderBot"
  description = "A Lex bot for ordering pizza."

  child_directed   = false
  create_version   = true
  locale           = "en-US"
  process_behavior = "BUILD"
  voice_id         = "Joanna"

  abort_statement {
    message {
      content      = "Sorry, I cannot help with that pizza order right now."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "I can help you order pizza. What would you like?"
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = aws_lex_intent.order_pizza.version
  }
}
