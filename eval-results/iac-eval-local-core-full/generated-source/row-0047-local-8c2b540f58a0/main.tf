resource "aws_lex_intent" "choose_pizza_size" {
  name        = "ChoosePizzaSize"
  description = "Collects the requested pizza size."

  sample_utterances = [
    "I want a small pizza",
    "I want a medium pizza",
    "I want a large pizza",
    "Make it extra large",
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_intent" "choose_pizza_crust" {
  name        = "ChoosePizzaCrust"
  description = "Collects the requested pizza crust style."

  sample_utterances = [
    "I want thin crust",
    "Make it deep dish",
    "Use stuffed crust",
    "I would like regular crust",
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_intent" "choose_pizza_toppings" {
  name        = "ChoosePizzaToppings"
  description = "Collects pizza topping preferences."

  sample_utterances = [
    "Add pepperoni",
    "I want mushrooms and olives",
    "Put sausage on my pizza",
    "Add extra cheese",
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_intent" "provide_delivery_details" {
  name        = "ProvideDeliveryDetails"
  description = "Collects delivery or pickup details for the pizza order."

  sample_utterances = [
    "Deliver it to my house",
    "I want pickup",
    "Send the pizza to my address",
    "I will collect my order",
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_intent" "confirm_pizza_order" {
  name        = "ConfirmPizzaOrder"
  description = "Confirms the completed pizza order."

  sample_utterances = [
    "Confirm my pizza order",
    "Place the order",
    "That is correct",
    "Finish my pizza order",
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_bot" "pizza_ordering" {
  name        = "PizzaOrderingBot"
  description = "Amazon Lex bot for ordering pizzas."

  child_directed              = false
  create_version              = false
  idle_session_ttl_in_seconds = 300
  locale                      = "en-US"
  process_behavior            = "BUILD"

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "I did not understand. What would you like for your pizza order?"
      content_type = "PlainText"
    }
  }

  abort_statement {
    message {
      content      = "Sorry, I cannot complete the pizza order right now."
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.choose_pizza_size.name
    intent_version = "$LATEST"
  }

  intent {
    intent_name    = aws_lex_intent.choose_pizza_crust.name
    intent_version = "$LATEST"
  }

  intent {
    intent_name    = aws_lex_intent.choose_pizza_toppings.name
    intent_version = "$LATEST"
  }

  intent {
    intent_name    = aws_lex_intent.provide_delivery_details.name
    intent_version = "$LATEST"
  }

  intent {
    intent_name    = aws_lex_intent.confirm_pizza_order.name
    intent_version = "$LATEST"
  }
}
