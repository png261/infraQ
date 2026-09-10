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
  region = "us-east-1"
}

resource "aws_lex_slot_type" "pizza_size" {
  name                     = "PizzaSize"
  description              = "Available pizza sizes"
  value_selection_strategy = "ORIGINAL_VALUE"
  create_version           = false

  enumeration_value {
    value    = "small"
    synonyms = ["personal", "little"]
  }

  enumeration_value {
    value    = "medium"
    synonyms = ["regular"]
  }

  enumeration_value {
    value    = "large"
    synonyms = ["big", "family size"]
  }
}

resource "aws_lex_slot_type" "pizza_crust" {
  name                     = "PizzaCrust"
  description              = "Available pizza crust options"
  value_selection_strategy = "ORIGINAL_VALUE"
  create_version           = false

  enumeration_value {
    value    = "thin"
    synonyms = ["thin crust"]
  }

  enumeration_value {
    value    = "regular"
    synonyms = ["classic", "standard"]
  }

  enumeration_value {
    value    = "stuffed"
    synonyms = ["cheese stuffed", "stuffed crust"]
  }
}

resource "aws_lex_slot_type" "pizza_topping" {
  name                     = "PizzaTopping"
  description              = "Available pizza toppings"
  value_selection_strategy = "ORIGINAL_VALUE"
  create_version           = false

  enumeration_value {
    value    = "cheese"
    synonyms = ["plain cheese"]
  }

  enumeration_value {
    value    = "pepperoni"
    synonyms = ["pepperoni pizza"]
  }

  enumeration_value {
    value    = "vegetable"
    synonyms = ["veggie", "vegetarian"]
  }

  enumeration_value {
    value    = "sausage"
    synonyms = ["Italian sausage"]
  }
}

resource "aws_lex_intent" "order_pizza" {
  name           = "OrderPizza"
  description    = "Intent for ordering a pizza"
  create_version = false

  sample_utterances = [
    "I want to order a pizza",
    "Order a pizza",
    "Can I get a pizza",
    "I would like a {Size} pizza",
    "I want a {Size} {Topping} pizza",
    "Get me a {Size} pizza with {Topping}",
    "I want a {Size} {Crust} crust pizza",
    "Order a {Size} {Crust} crust {Topping} pizza"
  ]

  slot {
    name              = "Size"
    description       = "The size of the pizza"
    slot_constraint   = "Required"
    slot_type         = aws_lex_slot_type.pizza_size.name
    slot_type_version = "$LATEST"
    priority          = 1

    sample_utterances = [
      "I want a {Size} pizza",
      "{Size}"
    ]

    value_elicitation_prompt {
      max_attempts = 2

      messages {
        content_type = "PlainText"
        content      = "What size pizza would you like: small, medium, or large?"
      }
    }
  }

  slot {
    name              = "Crust"
    description       = "The crust type for the pizza"
    slot_constraint   = "Required"
    slot_type         = aws_lex_slot_type.pizza_crust.name
    slot_type_version = "$LATEST"
    priority          = 2

    sample_utterances = [
      "I want {Crust} crust",
      "{Crust}"
    ]

    value_elicitation_prompt {
      max_attempts = 2

      messages {
        content_type = "PlainText"
        content      = "What type of crust would you like: thin, regular, or stuffed?"
      }
    }
  }

  slot {
    name              = "Topping"
    description       = "The main pizza topping"
    slot_constraint   = "Required"
    slot_type         = aws_lex_slot_type.pizza_topping.name
    slot_type_version = "$LATEST"
    priority          = 3

    sample_utterances = [
      "I want {Topping}",
      "{Topping}"
    ]

    value_elicitation_prompt {
      max_attempts = 2

      messages {
        content_type = "PlainText"
        content      = "What topping would you like: cheese, pepperoni, vegetable, or sausage?"
      }
    }
  }

  confirmation_prompt {
    max_attempts = 2

    messages {
      content_type = "PlainText"
      content      = "Please confirm: you want a {Size} pizza with {Crust} crust and {Topping}. Is that correct?"
    }
  }

  rejection_statement {
    messages {
      content_type = "PlainText"
      content      = "Okay, I have cancelled the pizza order."
    }
  }

  follow_up_prompt {
    prompt {
      max_attempts = 2

      messages {
        content_type = "PlainText"
        content      = "Your pizza order has been received. Would you like to add drinks or sides to your order?"
      }
    }

    rejection_statement {
      messages {
        content_type = "PlainText"
        content      = "No problem. Your pizza order is complete."
      }
    }
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }

  depends_on = [
    aws_lex_slot_type.pizza_size,
    aws_lex_slot_type.pizza_crust,
    aws_lex_slot_type.pizza_topping
  ]
}

resource "aws_lex_bot" "pizza_ordering_bot" {
  name        = "PizzaOrderingBot"
  description = "Amazon Lex bot for ordering pizza with a follow-up question"

  locale           = "en-US"
  child_directed   = false
  process_behavior = "BUILD"

  voice_id = "Joanna"

  idle_session_ttl_in_seconds = 300

  abort_statement {
    messages {
      content_type = "PlainText"
      content      = "Sorry, I could not complete your pizza order. Please try again later."
    }
  }

  clarification_prompt {
    max_attempts = 2

    messages {
      content_type = "PlainText"
      content      = "I can help you order a pizza. You can say, order a pizza."
    }
  }

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = "$LATEST"
  }

  depends_on = [
    aws_lex_intent.order_pizza
  ]
}

output "lex_bot_name" {
  description = "Name of the Amazon Lex pizza ordering bot"
  value       = aws_lex_bot.pizza_ordering_bot.name
}

output "lex_bot_arn" {
  description = "ARN of the Amazon Lex pizza ordering bot"
  value       = aws_lex_bot.pizza_ordering_bot.arn
}