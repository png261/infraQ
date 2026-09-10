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

resource "aws_lex_slot_type" "pizza_type" {
  name                     = "PizzaType"
  description              = "Types of pizzas available for ordering"
  create_version           = false
  value_selection_strategy = "ORIGINAL_VALUE"

  enumeration_value {
    value    = "cheese"
    synonyms = ["plain", "classic cheese"]
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
    value    = "margherita"
    synonyms = ["margarita"]
  }

  enumeration_value {
    value    = "hawaiian"
    synonyms = ["pineapple", "ham and pineapple"]
  }
}

resource "aws_lex_slot_type" "pizza_size" {
  name                     = "PizzaSize"
  description              = "Pizza sizes available for ordering"
  create_version           = false
  value_selection_strategy = "ORIGINAL_VALUE"

  enumeration_value {
    value    = "small"
    synonyms = ["personal"]
  }

  enumeration_value {
    value    = "medium"
    synonyms = ["regular"]
  }

  enumeration_value {
    value    = "large"
    synonyms = ["big"]
  }

  enumeration_value {
    value    = "extra large"
    synonyms = ["xl", "extra-large"]
  }
}

resource "aws_lex_intent" "order_pizza" {
  name           = "OrderPizza"
  description    = "Intent for ordering pizzas"
  create_version = false

  sample_utterances = [
    "I want to order a pizza",
    "Order a pizza",
    "Can I get a pizza",
    "I would like {Quantity} {PizzaSize} {PizzaType} pizzas",
    "Get me a {PizzaSize} {PizzaType} pizza",
    "I want {Quantity} {PizzaType} pizzas",
    "Order {Quantity} {PizzaSize} pizzas"
  ]

  slot {
    name                  = "PizzaSize"
    description           = "The size of the pizza"
    slot_constraint       = "Required"
    slot_type             = aws_lex_slot_type.pizza_size.name
    slot_type_version     = "$LATEST"
    priority              = 1
    sample_utterances     = ["{PizzaSize}"]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What size pizza would you like? You can choose small, medium, large, or extra large."
      }
    }
  }

  slot {
    name                  = "PizzaType"
    description           = "The type of pizza"
    slot_constraint       = "Required"
    slot_type             = aws_lex_slot_type.pizza_type.name
    slot_type_version     = "$LATEST"
    priority              = 2
    sample_utterances     = ["{PizzaType}"]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What type of pizza would you like? For example, cheese, pepperoni, vegetarian, margherita, or hawaiian."
      }
    }
  }

  slot {
    name                  = "Quantity"
    description           = "The number of pizzas to order"
    slot_constraint       = "Required"
    slot_type             = "AMAZON.NUMBER"
    priority              = 3
    sample_utterances     = ["{Quantity}"]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "How many pizzas would you like?"
      }
    }
  }

  confirmation_prompt {
    max_attempts = 2

    message {
      content_type = "PlainText"
      content      = "Please confirm: you want {Quantity} {PizzaSize} {PizzaType} pizza or pizzas. Is that correct?"
    }
  }

  rejection_statement {
    message {
      content_type = "PlainText"
      content      = "Okay, I have cancelled your pizza order."
    }
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_bot" "pizza_ordering_bot" {
  name           = "PizzaOrderingBot"
  description    = "Amazon Lex bot for ordering pizzas"
  locale         = "en-US"
  child_directed = false

  voice_id         = "Joanna"
  idle_session_ttl = 300

  process_behavior = "BUILD"
  create_version   = false

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = "$LATEST"
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content_type = "PlainText"
      content      = "Sorry, I did not understand. You can say something like, I want to order a pepperoni pizza."
    }
  }

  abort_statement {
    message {
      content_type = "PlainText"
      content      = "Sorry, I could not understand your request. Please try again later."
    }
  }

  conclusion_statement {
    message {
      content_type = "PlainText"
      content      = "Thank you for ordering pizza with us. Your order has been received and will be prepared soon."
    }
  }

  depends_on = [
    aws_lex_intent.order_pizza
  ]
}