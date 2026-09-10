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

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "daily-eventbridge-code-runner"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    filename = "lambda_function.py"
    content  = <<EOF
import json
from datetime import datetime, timezone

def lambda_handler(event, context):
    now = datetime.now(timezone.utc).isoformat()
    print(f"Daily scheduled code executed at {now}")
    print("Event received:", json.dumps(event))

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Daily code executed successfully",
            "executed_at_utc": now
        })
    }
EOF
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

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "daily_code_runner" {
  function_name = "${var.project_name}-lambda"
  role          = aws_iam_role.lambda_execution_role.arn

  runtime = "python3.12"
  handler = "lambda_function.lambda_handler"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = 30
  memory_size = 128

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]
}

resource "aws_cloudwatch_event_rule" "daily_7_utc" {
  name        = "${var.project_name}-daily-7-utc"
  description = "Runs the Lambda function every day at 07:00 UTC."

  schedule_expression = "cron(0 7 * * ? *)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_7_utc.name
  target_id = "DailyLambdaTarget"
  arn       = aws_lambda_function.daily_code_runner.arn
}

resource "aws_lambda_permission" "allow_eventbridge_invocation" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.daily_code_runner.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_7_utc.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function executed daily."
  value       = aws_lambda_function.daily_code_runner.function_name
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule."
  value       = aws_cloudwatch_event_rule.daily_7_utc.name
}

output "schedule_expression" {
  description = "EventBridge schedule expression."
  value       = aws_cloudwatch_event_rule.daily_7_utc.schedule_expression
}