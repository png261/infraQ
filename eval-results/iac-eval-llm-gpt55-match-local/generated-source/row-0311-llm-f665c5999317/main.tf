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
  default     = "daily-7am-utc-lambda"
}

variable "eventbridge_rule_name" {
  description = "Name of the EventBridge scheduled rule."
  type        = string
  default     = "daily-7am-utc-schedule"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    filename = "index.py"
    content  = <<EOF
import json
from datetime import datetime, timezone

def lambda_handler(event, context):
    now = datetime.now(timezone.utc).isoformat()
    print(f"Lambda executed successfully at {now}")
    print("Received event:", json.dumps(event))

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Daily Lambda execution completed successfully.",
            "executed_at_utc": now
        })
    }
EOF
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

resource "aws_iam_policy" "lambda_logging_policy" {
  name        = "${var.lambda_function_name}-logging-policy"
  description = "Allows Lambda to write logs to CloudWatch Logs."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda_logs.arn}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logging_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_logging_policy.arn
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 14
}

resource "aws_lambda_function" "daily_lambda" {
  function_name = var.lambda_function_name
  description   = "Lambda function triggered every day at 07:00 UTC by EventBridge."

  role    = aws_iam_role.lambda_execution_role.arn
  handler = "index.lambda_handler"
  runtime = "python3.12"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = 30
  memory_size = 128

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logging_attachment,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

resource "aws_cloudwatch_event_rule" "daily_schedule" {
  name        = var.eventbridge_rule_name
  description = "Triggers the Lambda function every day at 07:00 UTC."

  schedule_expression = "cron(0 7 * * ? *)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_schedule.name
  target_id = "daily-lambda-target"
  arn       = aws_lambda_function.daily_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.daily_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_schedule.arn
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
  description = "Name of the EventBridge schedule rule."
  value       = aws_cloudwatch_event_rule.daily_schedule.name
}

output "eventbridge_schedule_expression" {
  description = "Schedule expression used by EventBridge."
  value       = aws_cloudwatch_event_rule.daily_schedule.schedule_expression
}