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
  create_version           = true

  enumeration_value {
    value    = "small"
    synonyms = ["personal", "mini"]
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
    synonyms = ["xl", "family size"]
  }
}

resource "aws_lex_slot_type" "pizza_crust" {
  name                     = "PizzaCrust"
  description              = "Available pizza crust types"
  value_selection_strategy = "ORIGINAL_VALUE"
  create_version           = true

  enumeration_value {
    value    = "thin"
    synonyms = ["thin crust"]
  }

  enumeration_value {
    value    = "regular"
    synonyms = ["classic"]
  }

  enumeration_value {
    value    = "stuffed"
    synonyms = ["cheese stuffed"]
  }

  enumeration_value {
    value    = "gluten free"
    synonyms = ["gluten-free"]
  }
}

resource "aws_lex_slot_type" "pizza_topping" {
  name                     = "PizzaTopping"
  description              = "Available pizza toppings"
  value_selection_strategy = "ORIGINAL_VALUE"
  create_version           = true

  enumeration_value {
    value    = "pepperoni"
    synonyms = ["pep"]
  }

  enumeration_value {
    value    = "cheese"
    synonyms = ["plain cheese"]
  }

  enumeration_value {
    value    = "mushrooms"
    synonyms = ["mushroom"]
  }

  enumeration_value {
    value    = "sausage"
    synonyms = ["italian sausage"]
  }

  enumeration_value {
    value    = "vegetables"
    synonyms = ["veggie", "veggies"]
  }
}

resource "aws_lex_intent" "order_pizza" {
  name           = "OrderPizzaIntent"
  description    = "Intent for ordering a pizza"
  create_version = true

  sample_utterances = [
    "I want to order a pizza",
    "Order me a {PizzaSize} pizza",
    "Can I get a {PizzaSize} {PizzaTopping} pizza",
    "I would like a {PizzaSize} pizza with {PizzaTopping}",
    "Get me a {PizzaSize} pizza with {PizzaCrust} crust",
    "I want a {PizzaSize} {PizzaCrust} crust pizza"
  ]

  slot {
    name                  = "PizzaSize"
    description           = "The size of the pizza"
    priority              = 1
    slot_constraint       = "Required"
    slot_type             = aws_lex_slot_type.pizza_size.name
    slot_type_version     = aws_lex_slot_type.pizza_size.version
    sample_utterances     = ["I want a {PizzaSize} pizza", "{PizzaSize}"]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What size pizza would you like: small, medium, large, or extra large?"
        content_type = "PlainText"
      }
    }
  }

  slot {
    name                  = "PizzaCrust"
    description           = "The pizza crust type"
    priority              = 2
    slot_constraint       = "Required"
    slot_type             = aws_lex_slot_type.pizza_crust.name
    slot_type_version     = aws_lex_slot_type.pizza_crust.version
    sample_utterances     = ["I want {PizzaCrust} crust", "{PizzaCrust}"]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What type of crust would you like: thin, regular, stuffed, or gluten free?"
        content_type = "PlainText"
      }
    }
  }

  slot {
    name                  = "PizzaTopping"
    description           = "The main pizza topping"
    priority              = 3
    slot_constraint       = "Required"
    slot_type             = aws_lex_slot_type.pizza_topping.name
    slot_type_version     = aws_lex_slot_type.pizza_topping.version
    sample_utterances     = ["Add {PizzaTopping}", "I want {PizzaTopping}", "{PizzaTopping}"]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What topping would you like?"
        content_type = "PlainText"
      }
    }
  }

  slot {
    name              = "Quantity"
    description       = "Number of pizzas"
    priority          = 4
    slot_constraint   = "Required"
    slot_type         = "AMAZON.NUMBER"
    sample_utterances = ["I want {Quantity}", "{Quantity} pizzas"]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "How many pizzas would you like?"
        content_type = "PlainText"
      }
    }
  }

  confirmation_prompt {
    max_attempts = 2

    message {
      content      = "Please confirm: you want {Quantity} {PizzaSize} pizza or pizzas with {PizzaCrust} crust and {PizzaTopping}. Is that correct?"
      content_type = "PlainText"
    }
  }

  rejection_statement {
    message {
      content      = "Okay, I will not place the pizza order."
      content_type = "PlainText"
    }
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_intent" "cancel_pizza_order" {
  name           = "CancelPizzaOrderIntent"
  description    = "Intent for canceling a pizza order"
  create_version = true

  sample_utterances = [
    "Cancel my pizza order",
    "I want to cancel my order",
    "Cancel order {OrderNumber}",
    "Please cancel pizza order {OrderNumber}",
    "Stop my pizza delivery"
  ]

  slot {
    name              = "OrderNumber"
    description       = "The customer's pizza order number"
    priority          = 1
    slot_constraint   = "Required"
    slot_type         = "AMAZON.NUMBER"
    sample_utterances = ["Order number {OrderNumber}", "{OrderNumber}"]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What is your order number?"
        content_type = "PlainText"
      }
    }
  }

  confirmation_prompt {
    max_attempts = 2

    message {
      content      = "Are you sure you want to cancel order {OrderNumber}?"
      content_type = "PlainText"
    }
  }

  rejection_statement {
    message {
      content      = "Okay, I will not cancel your order."
      content_type = "PlainText"
    }
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_intent" "track_pizza_order" {
  name           = "TrackPizzaOrderIntent"
  description    = "Intent for tracking a pizza order"
  create_version = true

  sample_utterances = [
    "Track my pizza order",
    "Where is my pizza",
    "Check order {OrderNumber}",
    "What is the status of my order",
    "Track pizza order {OrderNumber}"
  ]

  slot {
    name              = "OrderNumber"
    description       = "The customer's pizza order number"
    priority          = 1
    slot_constraint   = "Required"
    slot_type         = "AMAZON.NUMBER"
    sample_utterances = ["Order number {OrderNumber}", "{OrderNumber}"]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What order number would you like to track?"
        content_type = "PlainText"
      }
    }
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_intent" "modify_pizza_order" {
  name           = "ModifyPizzaOrderIntent"
  description    = "Intent for modifying an existing pizza order"
  create_version = true

  sample_utterances = [
    "Modify my pizza order",
    "Change my order",
    "Update order {OrderNumber}",
    "I want to change order {OrderNumber}",
    "Change my pizza to {PizzaSize}",
    "Update my topping to {PizzaTopping}"
  ]

  slot {
    name              = "OrderNumber"
    description       = "The customer's pizza order number"
    priority          = 1
    slot_constraint   = "Required"
    slot_type         = "AMAZON.NUMBER"
    sample_utterances = ["Order number {OrderNumber}", "{OrderNumber}"]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What is the order number you want to modify?"
        content_type = "PlainText"
      }
    }
  }

  slot {
    name                  = "PizzaSize"
    description           = "Updated pizza size"
    priority              = 2
    slot_constraint       = "Optional"
    slot_type             = aws_lex_slot_type.pizza_size.name
    slot_type_version     = aws_lex_slot_type.pizza_size.version
    sample_utterances     = ["Make it {PizzaSize}", "{PizzaSize}"]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What size would you like to change the pizza to?"
        content_type = "PlainText"
      }
    }
  }

  slot {
    name                  = "PizzaTopping"
    description           = "Updated pizza topping"
    priority              = 3
    slot_constraint       = "Optional"
    slot_type             = aws_lex_slot_type.pizza_topping.name
    slot_type_version     = aws_lex_slot_type.pizza_topping.version
    sample_utterances     = ["Change topping to {PizzaTopping}", "{PizzaTopping}"]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What topping would you like instead?"
        content_type = "PlainText"
      }
    }
  }

  confirmation_prompt {
    max_attempts = 2

    message {
      content      = "Please confirm that you want to modify order {OrderNumber}."
      content_type = "PlainText"
    }
  }

  rejection_statement {
    message {
      content      = "Okay, I will not modify your order."
      content_type = "PlainText"
    }
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_intent" "pizza_help" {
  name           = "PizzaHelpIntent"
  description    = "Intent for pizza ordering help"
  create_version = true

  sample_utterances = [
    "Help",
    "I need help",
    "What can I do",
    "How do I order pizza",
    "What pizza options do you have",
    "Tell me how this works"
  ]

  conclusion_statement {
    message {
      content      = "You can order, cancel, track, or modify a pizza order. For example, say: I want to order a large pepperoni pizza."
      content_type = "PlainText"
    }
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_bot" "pizza_ordering_bot" {
  name                        = "PizzaOrderingBot"
  description                 = "AWS Lex bot for ordering pizzas with ordering, canceling, tracking, modifying, and help intents."
  locale                      = "en-US"
  child_directed              = false
  idle_session_ttl_in_seconds = 300
  process_behavior            = "BUILD"
  voice_id                    = "Joanna"

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "Sorry, I did not understand. You can say things like order a pizza, track my order, cancel my order, modify my order, or help."
      content_type = "PlainText"
    }
  }

  abort_statement {
    message {
      content      = "Sorry, I could not understand your request. Please try again later."
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = aws_lex_intent.order_pizza.version
  }

  intent {
    intent_name    = aws_lex_intent.cancel_pizza_order.name
    intent_version = aws_lex_intent.cancel_pizza_order.version
  }

  intent {
    intent_name    = aws_lex_intent.track_pizza_order.name
    intent_version = aws_lex_intent.track_pizza_order.version
  }

  intent {
    intent_name    = aws_lex_intent.modify_pizza_order.name
    intent_version = aws_lex_intent.modify_pizza_order.version
  }

  intent {
    intent_name    = aws_lex_intent.pizza_help.name
    intent_version = aws_lex_intent.pizza_help.version
  }

  depends_on = [
    aws_lex_intent.order_pizza,
    aws_lex_intent.cancel_pizza_order,
    aws_lex_intent.track_pizza_order,
    aws_lex_intent.modify_pizza_order,
    aws_lex_intent.pizza_help
  ]
}

output "lex_bot_name" {
  value = aws_lex_bot.pizza_ordering_bot.name
}

output "lex_bot_arn" {
  value = aws_lex_bot.pizza_ordering_bot.arn
}