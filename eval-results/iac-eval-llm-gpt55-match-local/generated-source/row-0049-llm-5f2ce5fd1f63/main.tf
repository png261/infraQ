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

resource "aws_lex_slot_type" "pizza_crust" {
  name                     = "PizzaCrust"
  description              = "Available pizza crust types"
  create_version           = true
  value_selection_strategy = "ORIGINAL_VALUE"

  enumeration_value {
    value = "thin"
  }

  enumeration_value {
    value = "regular"
  }

  enumeration_value {
    value = "deep dish"
  }

  enumeration_value {
    value = "stuffed"
  }
}

resource "aws_lex_slot_type" "pizza_topping" {
  name                     = "PizzaTopping"
  description              = "Available pizza toppings"
  create_version           = true
  value_selection_strategy = "ORIGINAL_VALUE"

  enumeration_value {
    value = "cheese"
  }

  enumeration_value {
    value = "pepperoni"
  }

  enumeration_value {
    value = "mushrooms"
  }

  enumeration_value {
    value = "sausage"
  }

  enumeration_value {
    value = "vegetables"
  }
}

resource "aws_lex_intent" "order_pizza" {
  name           = "OrderPizza"
  description    = "Intent for ordering a pizza"
  create_version = true

  sample_utterances = [
    "I want to order a pizza",
    "Order a pizza",
    "Can I get a pizza",
    "I would like a {Size} pizza",
    "I want a {Size} {Crust} crust pizza",
    "Order me a {Size} pizza with {Topping}",
    "Can I get a {Size} pizza with {Topping}"
  ]

  slot {
    name            = "Size"
    description     = "The size of the pizza"
    slot_constraint = "Required"
    slot_type       = aws_lex_slot_type.pizza_size.name
    priority        = 1

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What size pizza would you like? Small, medium, or large?"
      }
    }
  }

  slot {
    name            = "Crust"
    description     = "The crust type for the pizza"
    slot_constraint = "Required"
    slot_type       = aws_lex_slot_type.pizza_crust.name
    priority        = 2

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What type of crust would you like? Thin, regular, deep dish, or stuffed?"
      }
    }
  }

  slot {
    name            = "Topping"
    description     = "The primary topping for the pizza"
    slot_constraint = "Required"
    slot_type       = aws_lex_slot_type.pizza_topping.name
    priority        = 3

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What topping would you like on your pizza?"
      }
    }
  }

  confirmation_prompt {
    max_attempts = 2

    message {
      content_type = "PlainText"
      content      = "You want a {Size} pizza with {Crust} crust and {Topping}. Is that correct?"
    }
  }

  rejection_statement {
    message {
      content_type = "PlainText"
      content      = "Okay, I will cancel the pizza order."
    }
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }

  conclusion_statement {
    message {
      content_type = "PlainText"
      content      = "Great, your {Size} pizza with {Crust} crust and {Topping} has been ordered."
    }
  }

  depends_on = [
    aws_lex_slot_type.pizza_size,
    aws_lex_slot_type.pizza_crust,
    aws_lex_slot_type.pizza_topping
  ]
}

resource "aws_lex_bot" "pizza_ordering_bot" {
  name        = "PizzaOrderingBot"
  description = "AWS Lex bot for ordering pizzas"

  child_directed                  = false
  idle_session_ttl_in_seconds      = 300
  locale                          = "en-US"
  process_behavior                = "BUILD"
  voice_id                        = "Joanna"
  nlu_intent_confidence_threshold = 0.5

  abort_statement {
    message {
      content_type = "PlainText"
      content      = "Sorry, I could not understand your pizza order. Please try again later."
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content_type = "PlainText"
      content      = "I did not understand. You can say something like, I want to order a large pepperoni pizza."
    }
  }

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = aws_lex_intent.order_pizza.version
  }

  depends_on = [
    aws_lex_intent.order_pizza
  ]
}