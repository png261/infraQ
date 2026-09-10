terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pizza_lambda" {
  name               = "pizza-order-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "pizza_lambda_basic" {
  role       = aws_iam_role.pizza_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "pizza_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/pizza_order.py"
  output_path = "${path.module}/build/pizza_order.zip"
}

resource "aws_lambda_function" "pizza_order" {
  function_name    = "pizza-order-fulfillment"
  description      = "Fulfillment hook for the Lex pizza ordering bot."
  role             = aws_iam_role.pizza_lambda.arn
  handler          = "pizza_order.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.pizza_lambda.output_path
  source_code_hash = data.archive_file.pizza_lambda.output_base64sha256

  depends_on = [aws_iam_role_policy_attachment.pizza_lambda_basic]
}

resource "aws_lambda_permission" "allow_lex" {
  statement_id  = "AllowExecutionFromLexPizzaBot"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pizza_order.function_name
  principal     = "lex.amazonaws.com"
}

resource "aws_lex_intent" "order_pizza" {
  name        = "OrderPizza"
  description = "Collects a pizza order and invokes Lambda fulfillment."

  sample_utterances = [
    "I want to order a pizza",
    "Order a pizza",
    "Can I get a pizza",
    "Pizza delivery please"
  ]

  dialog_code_hook {
    message_version = "1.0"
    uri             = aws_lambda_function.pizza_order.arn
  }

  fulfillment_activity {
    type = "CodeHook"

    code_hook {
      message_version = "1.0"
      uri             = aws_lambda_function.pizza_order.arn
    }
  }
}

resource "aws_lex_bot" "pizza_order" {
  name           = "PizzaOrderBot"
  description    = "A minimal Lex bot for ordering pizzas."
  locale         = "en-US"
  child_directed = false

  abort_statement {
    message {
      content      = "Sorry, I could not complete your pizza order."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "How can I help with your pizza order?"
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = "$LATEST"
  }

  idle_session_ttl_in_seconds = 300
  process_behavior            = "BUILD"
}
