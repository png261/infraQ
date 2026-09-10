terraform {
  required_version = ">= 1.0.0"

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
  name        = "PizzaSize"
  description = "Available pizza sizes"

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

  value_selection_strategy = "ORIGINAL_VALUE"
}

resource "aws_lex_slot_type" "pizza_crust" {
  name        = "PizzaCrust"
  description = "Available pizza crust types"

  enumeration_value {
    value    = "thin"
    synonyms = ["thin crust", "crispy"]
  }

  enumeration_value {
    value    = "regular"
    synonyms = ["classic", "standard"]
  }

  enumeration_value {
    value    = "deep dish"
    synonyms = ["pan", "thick"]
  }

  value_selection_strategy = "ORIGINAL_VALUE"
}

resource "aws_lex_slot_type" "pizza_topping" {
  name        = "PizzaTopping"
  description = "Available pizza toppings"

  enumeration_value {
    value    = "cheese"
    synonyms = ["plain cheese"]
  }

  enumeration_value {
    value    = "pepperoni"
    synonyms = ["pepperoni pizza"]
  }

  enumeration_value {
    value    = "vegetarian"
    synonyms = ["veggie", "vegetable"]
  }

  enumeration_value {
    value    = "mushroom"
    synonyms = ["mushrooms"]
  }

  value_selection_strategy = "ORIGINAL_VALUE"
}

resource "aws_lex_intent" "order_pizza" {
  name        = "OrderPizza"
  description = "Intent for ordering a pizza"

  sample_utterances = [
    "I want to order a pizza",
    "Order a pizza",
    "Can I get a pizza",
    "I would like a pizza",
    "Get me a {PizzaSize} pizza",
    "I want a {PizzaSize} {PizzaTopping} pizza",
    "Order a {PizzaSize} pizza with {PizzaTopping}",
    "I want a {PizzaSize} {PizzaCrust} crust pizza with {PizzaTopping}"
  ]

  slot {
    name              = "PizzaSize"
    description       = "The size of the pizza"
    priority          = 1
    slot_constraint   = "Required"
    slot_type         = aws_lex_slot_type.pizza_size.name
    slot_type_version = "$LATEST"

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What size pizza would you like? You can say small, medium, or large."
        content_type = "PlainText"
      }
    }

    sample_utterances = [
      "I want a {PizzaSize} pizza",
      "{PizzaSize}"
    ]
  }

  slot {
    name              = "PizzaCrust"
    description       = "The crust type for the pizza"
    priority          = 2
    slot_constraint   = "Required"
    slot_type         = aws_lex_slot_type.pizza_crust.name
    slot_type_version = "$LATEST"

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What kind of crust would you like? Thin, regular, or deep dish?"
        content_type = "PlainText"
      }
    }

    sample_utterances = [
      "I want {PizzaCrust} crust",
      "{PizzaCrust}"
    ]
  }

  slot {
    name              = "PizzaTopping"
    description       = "The main topping for the pizza"
    priority          = 3
    slot_constraint   = "Required"
    slot_type         = aws_lex_slot_type.pizza_topping.name
    slot_type_version = "$LATEST"

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What topping would you like? You can say cheese, pepperoni, vegetarian, or mushroom."
        content_type = "PlainText"
      }
    }

    sample_utterances = [
      "I want {PizzaTopping}",
      "{PizzaTopping}"
    ]
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }

  conclusion_statement {
    message {
      content      = "Thanks, your {PizzaSize} {PizzaCrust} crust pizza with {PizzaTopping} has been ordered."
      content_type = "PlainText"
    }
  }

  depends_on = [
    aws_lex_slot_type.pizza_size,
    aws_lex_slot_type.pizza_crust,
    aws_lex_slot_type.pizza_topping
  ]
}

resource "aws_lex_bot" "pizza_order_bot" {
  name        = "PizzaOrderBot"
  description = "A Lex bot that helps customers order pizzas"

  locale                        = "en-US"
  child_directed                = false
  idle_session_ttl_in_seconds   = 300
  process_behavior              = "BUILD"
  voice_id                      = "Joanna"
  enable_model_improvements     = true

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "Sorry, I did not understand that. You can say something like, I want to order a pizza."
      content_type = "PlainText"
    }
  }

  abort_statement {
    message {
      content      = "Sorry, I am unable to help with your pizza order right now."
      content_type = "PlainText"
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