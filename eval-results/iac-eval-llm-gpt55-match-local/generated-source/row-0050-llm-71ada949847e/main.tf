terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Name prefix for all resources."
  default     = "pizza-ordering-lex"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "archive_file" "pizza_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/pizza_order_fulfillment.zip"

  source {
    filename = "lambda_function.py"

    content = <<PYTHON
import json

def lambda_handler(event, context):
    print("Received event:", json.dumps(event))

    slots = event.get("currentIntent", {}).get("slots", {})

    pizza_size = slots.get("PizzaSize") or "medium"
    crust_type = slots.get("CrustType") or "regular"
    quantity = slots.get("Quantity") or "1"
    address = slots.get("DeliveryAddress") or "your address"

    message = (
        f"Thanks! Your order for {quantity} {pizza_size} pizza(s) "
        f"with {crust_type} crust will be delivered to {address}."
    )

    return {
        "dialogAction": {
            "type": "Close",
            "fulfillmentState": "Fulfilled",
            "message": {
                "contentType": "PlainText",
                "content": message
            }
        }
    }
PYTHON
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_logging_policy" {
  name = "${var.project_name}-lambda-logging-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

resource "aws_lambda_function" "pizza_order_fulfillment" {
  function_name = "${var.project_name}-fulfillment"
  description   = "Lambda fulfillment function for the pizza ordering Lex bot."

  role    = aws_iam_role.lambda_execution_role.arn
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"

  filename         = data.archive_file.pizza_lambda_zip.output_path
  source_code_hash = data.archive_file.pizza_lambda_zip.output_base64sha256

  depends_on = [
    aws_iam_role_policy.lambda_logging_policy
  ]
}

resource "aws_lambda_permission" "allow_lex_invoke" {
  statement_id  = "AllowExecutionFromLex"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pizza_order_fulfillment.function_name
  principal     = "lex.amazonaws.com"
}

resource "aws_lex_slot_type" "pizza_size" {
  name                     = "PizzaSize"
  description              = "Available pizza sizes."
  create_version           = true
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
    synonyms = ["big", "family"]
  }
}

resource "aws_lex_slot_type" "crust_type" {
  name                     = "CrustType"
  description              = "Available pizza crust types."
  create_version           = true
  value_selection_strategy = "ORIGINAL_VALUE"

  enumeration_value {
    value    = "thin"
    synonyms = ["crispy"]
  }

  enumeration_value {
    value    = "regular"
    synonyms = ["classic"]
  }

  enumeration_value {
    value    = "stuffed"
    synonyms = ["cheese stuffed"]
  }
}

resource "aws_lex_intent" "order_pizza" {
  name           = "OrderPizza"
  description    = "Intent for ordering pizza."
  create_version = true

  sample_utterances = [
    "I want to order a pizza",
    "Order pizza",
    "Can I get a pizza",
    "I would like a pizza",
    "Please order a pizza for me",
    "Get me a pizza",
    "I want {Quantity} {PizzaSize} pizzas",
    "Order {Quantity} {PizzaSize} pizza with {CrustType} crust"
  ]

  slot {
    name              = "PizzaSize"
    description       = "The size of the pizza."
    slot_constraint   = "Required"
    slot_type         = aws_lex_slot_type.pizza_size.name
    slot_type_version = aws_lex_slot_type.pizza_size.version
    priority          = 1

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What size pizza would you like: small, medium, or large?"
      }
    }

    sample_utterances = [
      "I want a {PizzaSize} pizza",
      "{PizzaSize}"
    ]
  }

  slot {
    name              = "CrustType"
    description       = "The crust type for the pizza."
    slot_constraint   = "Required"
    slot_type         = aws_lex_slot_type.crust_type.name
    slot_type_version = aws_lex_slot_type.crust_type.version
    priority          = 2

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What crust would you like: thin, regular, or stuffed?"
      }
    }

    sample_utterances = [
      "I want {CrustType} crust",
      "{CrustType}"
    ]
  }

  slot {
    name            = "Quantity"
    description     = "The number of pizzas to order."
    slot_constraint = "Required"
    slot_type       = "AMAZON.NUMBER"
    priority        = 3

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "How many pizzas would you like?"
      }
    }

    sample_utterances = [
      "I want {Quantity}",
      "{Quantity}"
    ]
  }

  slot {
    name            = "DeliveryAddress"
    description     = "The delivery address."
    slot_constraint = "Required"
    slot_type       = "AMAZON.StreetAddress"
    priority        = 4

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What is the delivery address?"
      }
    }

    sample_utterances = [
      "Deliver to {DeliveryAddress}",
      "{DeliveryAddress}"
    ]
  }

  fulfillment_activity {
    type = "CodeHook"

    code_hook {
      message_version = "1.0"
      uri             = aws_lambda_function.pizza_order_fulfillment.arn
    }
  }

  conclusion_statement {
    message {
      content_type = "PlainText"
      content      = "Your pizza order has been placed."
    }
  }

  depends_on = [
    aws_lambda_permission.allow_lex_invoke
  ]
}

resource "aws_lex_bot" "pizza_ordering_bot" {
  name        = "PizzaOrderingBot"
  description = "A Lex bot that helps customers order pizzas."

  child_directed              = false
  locale                      = "en-US"
  idle_session_ttl_in_seconds = 300
  process_behavior            = "BUILD"
  create_version              = true

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
      content      = "Sorry, I could not complete your pizza order. Please try again later."
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

output "lex_bot_name" {
  description = "Name of the created Lex pizza ordering bot."
  value       = aws_lex_bot.pizza_ordering_bot.name
}

output "lex_bot_arn" {
  description = "ARN of the created Lex pizza ordering bot."
  value       = aws_lex_bot.pizza_ordering_bot.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda fulfillment function."
  value       = aws_lambda_function.pizza_order_fulfillment.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda fulfillment function."
  value       = aws_lambda_function.pizza_order_fulfillment.arn
}