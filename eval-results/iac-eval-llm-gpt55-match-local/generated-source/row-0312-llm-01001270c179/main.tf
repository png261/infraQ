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
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function."
  type        = string
  default     = "daily-7utc-lambda"
}

variable "event_rule_name" {
  description = "Name of the EventBridge rule."
  type        = string
  default     = "daily-7utc-event-rule"
}

locals {
  lambda_source_code = <<-PYTHON
    import json
    import datetime

    def lambda_handler(event, context):
        now = datetime.datetime.utcnow().isoformat()

        message = {
            "message": "Lambda executed successfully.",
            "executed_at_utc": now,
            "event": event
        }

        print(json.dumps(message))

        return {
            "statusCode": 200,
            "body": json.dumps(message)
        }
  PYTHON
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    content  = local.lambda_source_code
    filename = "lambda_function.py"
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.lambda_function_name}-execution-role"

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

resource "aws_iam_role_policy" "lambda_basic_logging_policy" {
  name = "${var.lambda_function_name}-basic-logging-policy"
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
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "daily_lambda" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_execution_role.arn

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"

  timeout     = 30
  memory_size = 128

  depends_on = [
    aws_iam_role_policy.lambda_basic_logging_policy
  ]
}

resource "aws_cloudwatch_event_rule" "daily_7utc_rule" {
  name        = var.event_rule_name
  description = "Runs the Lambda function every day at 07:00 UTC."

  schedule_expression = "cron(0 7 * * ? *)"
}

resource "aws_cloudwatch_event_target" "daily_lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_7utc_rule.name
  target_id = "InvokeDailyLambda"
  arn       = aws_lambda_function.daily_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge_invoke" {
  statement_id  = "AllowExecutionFromEventBridgeDaily7UTC"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.daily_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_7utc_rule.arn
}

output "lambda_function_name" {
  description = "Name of the deployed Lambda function."
  value       = aws_lambda_function.daily_lambda.function_name
}

output "lambda_function_arn" {
  description = "ARN of the deployed Lambda function."
  value       = aws_lambda_function.daily_lambda.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule."
  value       = aws_cloudwatch_event_rule.daily_7utc_rule.name
}

output "eventbridge_schedule_expression" {
  description = "Schedule expression used by EventBridge."
  value       = aws_cloudwatch_event_rule.daily_7utc_rule.schedule_expression
}