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

resource "aws_iam_role" "lambda_execution_role" {
  name = "cron-lambda-execution-role"

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

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "cron" {
  function_name = "cron-lambda-function"
  filename      = "./supplement/lambda_func.zip"
  handler       = "lambda_func.lambda_handler"
  runtime       = "python3.12"
  role          = aws_iam_role.lambda_execution_role.arn

  source_code_hash = filebase64sha256("./supplement/lambda_func.zip")

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]
}

resource "aws_cloudwatch_event_rule" "cron" {
  name                = "cron"
  schedule_expression = "cron(0 7 * * ? *)"
}

resource "aws_cloudwatch_event_target" "cron" {
  rule      = aws_cloudwatch_event_rule.cron.name
  target_id = "cron-lambda-target"
  arn       = aws_lambda_function.cron.arn
}

resource "aws_lambda_permission" "cron" {
  statement_id  = "AllowExecutionFromEventBridgeCronRule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cron.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cron.arn
}