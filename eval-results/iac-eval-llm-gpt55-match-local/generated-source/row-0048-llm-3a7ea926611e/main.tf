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
  name                     = "KidsPizzaSize"
  description              = "Pizza sizes that kids can choose from."
  value_selection_strategy = "ORIGINAL_VALUE"

  enumeration_value {
    value    = "small"
    synonyms = ["little", "tiny", "kid size"]
  }

  enumeration_value {
    value    = "medium"
    synonyms = ["regular", "normal"]
  }

  enumeration_value {
    value    = "large"
    synonyms = ["big", "giant", "family size"]
  }
}

resource "aws_lex_slot_type" "pizza_crust" {
  name                     = "KidsPizzaCrust"
  description              = "Pizza crust choices suitable for kids."
  value_selection_strategy = "ORIGINAL_VALUE"

  enumeration_value {
    value    = "thin"
    synonyms = ["crispy", "thin crust"]
  }

  enumeration_value {
    value    = "regular"
    synonyms = ["classic", "normal"]
  }

  enumeration_value {
    value    = "stuffed"
    synonyms = ["cheesy crust", "cheese stuffed"]
  }
}

resource "aws_lex_slot_type" "pizza_topping" {
  name                     = "KidsPizzaTopping"
  description              = "Kid-friendly pizza toppings."
  value_selection_strategy = "ORIGINAL_VALUE"

  enumeration_value {
    value    = "cheese"
    synonyms = ["extra cheese", "plain cheese"]
  }

  enumeration_value {
    value    = "pepperoni"
    synonyms = ["pepperoni slices"]
  }

  enumeration_value {
    value    = "mushrooms"
    synonyms = ["mushroom"]
  }

  enumeration_value {
    value    = "pineapple"
    synonyms = ["sweet pineapple"]
  }

  enumeration_value {
    value    = "olives"
    synonyms = ["black olives"]
  }
}

resource "aws_lex_intent" "order_pizza" {
  name        = "OrderPizza"
  description = "Intent for helping kids order a pizza."

  sample_utterances = [
    "I want pizza",
    "Can I order a pizza",
    "I would like a {PizzaSize} pizza",
    "I want a {PizzaSize} pizza with {PizzaTopping}",
    "Order me a {PizzaSize} {PizzaCrust} pizza",
    "Can I have a {PizzaSize} pizza with {PizzaTopping}",
    "I want a {PizzaCrust} crust pizza",
    "Pizza please"
  ]

  slot {
    name              = "PizzaSize"
    description       = "The size of the pizza."
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

      message {
        content_type = "PlainText"
        content      = "Should your pizza be small like a snack, medium like lunch, or large to share?"
      }
    }
  }

  slot {
    name              = "PizzaCrust"
    description       = "The crust type for the pizza."
    slot_constraint   = "Required"
    slot_type         = aws_lex_slot_type.pizza_crust.name
    slot_type_version = "$LATEST"
    priority          = 2

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What kind of crust would you like: thin, regular, or stuffed?"
      }

      message {
        content_type = "PlainText"
        content      = "Pick a crust: crispy thin, classic regular, or cheesy stuffed."
      }
    }
  }

  slot {
    name              = "PizzaTopping"
    description       = "The main topping for the pizza."
    slot_constraint   = "Required"
    slot_type         = aws_lex_slot_type.pizza_topping.name
    slot_type_version = "$LATEST"
    priority          = 3

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What topping would you like? You can choose cheese, pepperoni, mushrooms, pineapple, or olives."
      }

      message {
        content_type = "PlainText"
        content      = "What yummy topping should go on your pizza?"
      }
    }
  }

  confirmation_prompt {
    max_attempts = 2

    message {
      content_type = "PlainText"
      content      = "Great choice! Do you want to order a {PizzaSize} pizza with {PizzaCrust} crust and {PizzaTopping}?"
    }
  }

  rejection_statement {
    message {
      content_type = "PlainText"
      content      = "No problem. We will not order the pizza right now."
    }
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }

  conclusion_statement {
    message {
      content_type = "PlainText"
      content      = "Yum! Your pizza order is ready to be sent to a grown-up for help."
    }
  }

  depends_on = [
    aws_lex_slot_type.pizza_size,
    aws_lex_slot_type.pizza_crust,
    aws_lex_slot_type.pizza_topping
  ]
}

resource "aws_lex_bot" "kids_pizza_order_bot" {
  name        = "KidsPizzaOrderBot"
  description = "A child-directed AWS Lex bot that helps kids choose and order a pizza."

  locale                        = "en-US"
  child_directed                = true
  idle_session_ttl_in_seconds   = 300
  voice_id                      = "Joanna"
  process_behavior              = "BUILD"

  clarification_prompt {
    max_attempts = 2

    message {
      content_type = "PlainText"
      content      = "Oops, I did not understand. Can you say that again?"
    }

    message {
      content_type = "PlainText"
      content      = "Can you tell me again what pizza you would like?"
    }
  }

  abort_statement {
    message {
      content_type = "PlainText"
      content      = "Sorry, I am having trouble helping right now. Please ask a grown-up for help."
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