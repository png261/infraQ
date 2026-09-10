terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function."
  type        = string
  default     = "invoke-every-15-minutes-lambda"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    filename = "index.py"
    content  = <<EOF
import json
import datetime

def handler(event, context):
    now = datetime.datetime.utcnow().isoformat()
    print(f"Lambda invoked at {now} UTC")
    print("Received event:", json.dumps(event))

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Lambda executed successfully",
            "invoked_at_utc": now
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

resource "aws_iam_role_policy" "lambda_logging_policy" {
  name = "${var.lambda_function_name}-logging-policy"
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
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_function" "scheduled_lambda" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_execution_role.arn

  runtime = "python3.12"
  handler = "index.handler"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = 30
  memory_size = 128

  depends_on = [
    aws_iam_role_policy.lambda_logging_policy
  ]
}

resource "aws_cloudwatch_event_rule" "every_15_minutes" {
  name                = "${var.lambda_function_name}-every-15-minutes"
  description         = "Invokes the Lambda function every 15 minutes."
  schedule_expression = "rate(15 minutes)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.every_15_minutes.name
  target_id = "InvokeLambdaEvery15Minutes"
  arn       = aws_lambda_function.scheduled_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge_invocation" {
  statement_id  = "AllowExecutionFromEventBridgeEvery15Minutes"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduled_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_15_minutes.arn
}

output "lambda_function_name" {
  description = "Name of the created Lambda function."
  value       = aws_lambda_function.scheduled_lambda.function_name
}

output "lambda_function_arn" {
  description = "ARN of the created Lambda function."
  value       = aws_lambda_function.scheduled_lambda.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule invoking the Lambda function."
  value       = aws_cloudwatch_event_rule.every_15_minutes.name
}