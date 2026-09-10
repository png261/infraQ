terraform {
  required_version = ">= 1.3.0"

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
  create_version           = false
  value_selection_strategy = "ORIGINAL_VALUE"

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
    synonyms = ["big", "family"]
  }
}

resource "aws_lex_slot_type" "pizza_crust" {
  name                     = "PizzaCrust"
  description              = "Available pizza crust types"
  create_version           = false
  value_selection_strategy = "ORIGINAL_VALUE"

  enumeration_value {
    value    = "thin"
    synonyms = ["thin crust"]
  }

  enumeration_value {
    value    = "regular"
    synonyms = ["classic", "hand tossed"]
  }

  enumeration_value {
    value    = "stuffed"
    synonyms = ["cheese stuffed", "stuffed crust"]
  }
}

resource "aws_lex_slot_type" "pizza_topping" {
  name                     = "PizzaTopping"
  description              = "Available pizza toppings"
  create_version           = false
  value_selection_strategy = "ORIGINAL_VALUE"

  enumeration_value {
    value    = "pepperoni"
    synonyms = ["pepperoni pizza"]
  }

  enumeration_value {
    value    = "cheese"
    synonyms = ["plain cheese"]
  }

  enumeration_value {
    value    = "veggie"
    synonyms = ["vegetarian", "vegetable"]
  }

  enumeration_value {
    value    = "sausage"
    synonyms = ["italian sausage"]
  }
}

resource "aws_lex_slot_type" "drink_choice" {
  name                     = "DrinkChoice"
  description              = "Available drink options"
  create_version           = false
  value_selection_strategy = "ORIGINAL_VALUE"

  enumeration_value {
    value    = "cola"
    synonyms = ["coke", "soda"]
  }

  enumeration_value {
    value    = "water"
    synonyms = ["bottled water"]
  }

  enumeration_value {
    value    = "lemonade"
    synonyms = ["lemon drink"]
  }

  enumeration_value {
    value    = "none"
    synonyms = ["no drink", "nothing", "no thanks"]
  }
}

resource "aws_lex_intent" "add_drink" {
  name           = "AddDrink"
  description    = "Captures whether the customer wants to add a drink"
  create_version = false

  sample_utterances = [
    "I want a drink",
    "Add a drink",
    "Yes add a drink",
    "I would like {Drink}",
    "Add {Drink}",
    "No drink",
    "Nothing else"
  ]

  slot {
    name              = "Drink"
    description       = "The drink the customer wants to add"
    slot_constraint   = "Required"
    slot_type         = aws_lex_slot_type.drink_choice.name
    slot_type_version = "$LATEST"
    priority          = 1

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What drink would you like? You can say cola, water, lemonade, or none."
      }
    }
  }

  confirmation_prompt {
    max_attempts = 2

    message {
      content_type = "PlainText"
      content      = "You chose {Drink}. Is that correct?"
    }
  }

  rejection_statement {
    message {
      content_type = "PlainText"
      content      = "Okay, I will not add that drink."
    }
  }

  fulfillment_activity {
    type = "ReturnIntent"
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
    "Order a {Size} pizza with {Topping}",
    "Get me a {Size} {Crust} crust pizza with {Topping}"
  ]

  slot {
    name              = "Size"
    description       = "The size of the pizza"
    slot_constraint   = "Required"
    slot_type         = aws_lex_slot_type.pizza_size.name
    slot_type_version = "$LATEST"
    priority          = 1

    value_elicitation_prompt {
      max_attempts = 2

      message {
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

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What type of crust would you like: thin, regular, or stuffed?"
      }
    }
  }

  slot {
    name              = "Topping"
    description       = "The main topping for the pizza"
    slot_constraint   = "Required"
    slot_type         = aws_lex_slot_type.pizza_topping.name
    slot_type_version = "$LATEST"
    priority          = 3

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What topping would you like: pepperoni, cheese, veggie, or sausage?"
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
      content      = "Okay, I have cancelled the pizza order."
    }
  }

  follow_up_prompt {
    prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "Would you like to add a drink to your pizza order?"
      }
    }

    rejection_statement {
      message {
        content_type = "PlainText"
        content      = "No problem. Your pizza order is ready to be submitted."
      }
    }
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_bot" "pizza_ordering_bot" {
  name                        = "PizzaOrderingBot"
  description                 = "A Lex bot that helps customers order pizza and asks a follow-up question about adding a drink"
  locale                      = "en-US"
  child_directed              = false
  idle_session_ttl_in_seconds = 300
  process_behavior            = "BUILD"
  create_version              = false

  clarification_prompt {
    max_attempts = 2

    message {
      content_type = "PlainText"
      content      = "Sorry, I did not understand that. You can say, I want to order a pizza."
    }
  }

  abort_statement {
    message {
      content_type = "PlainText"
      content      = "Sorry, I could not help with that request. Please try again later."
    }
  }

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = "$LATEST"
  }

  intent {
    intent_name    = aws_lex_intent.add_drink.name
    intent_version = "$LATEST"
  }

  depends_on = [
    aws_lex_intent.order_pizza,
    aws_lex_intent.add_drink
  ]
}

output "lex_bot_name" {
  value = aws_lex_bot.pizza_ordering_bot.name
}

output "lex_bot_arn" {
  value = aws_lex_bot.pizza_ordering_bot.arn
}