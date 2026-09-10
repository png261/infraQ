terraform {
  required_version = ">= 1.5.0"

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

data "archive_file" "example_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/example_lambda.zip"

  source {
    filename = "lambda_function.py"
    content  = <<EOF
import json

def lambda_handler(event, context):
    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Hello from example_lambda!",
            "input": event
        })
    }
EOF
  }
}

resource "aws_iam_role" "example_lambda_role" {
  name = "example_lambda_execution_role"

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

resource "aws_iam_role_policy_attachment" "example_lambda_basic_execution" {
  role       = aws_iam_role.example_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "example_lambda" {
  function_name = "example_lambda"
  role          = aws_iam_role.example_lambda_role.arn

  runtime = "python3.12"
  handler = "lambda_function.lambda_handler"

  filename         = data.archive_file.example_lambda_zip.output_path
  source_code_hash = data.archive_file.example_lambda_zip.output_base64sha256

  depends_on = [
    aws_iam_role_policy_attachment.example_lambda_basic_execution
  ]
}

data "aws_lambda_invocation" "example_lambda_invocation" {
  function_name = aws_lambda_function.example_lambda.function_name

  input = jsonencode({
    invoked_by = "terraform"
    message    = "Invoke example_lambda lambda_function"
  })

  depends_on = [
    aws_lambda_function.example_lambda
  ]
}

output "lambda_function_name" {
  description = "Name of the created Lambda function."
  value       = aws_lambda_function.example_lambda.function_name
}

output "lambda_invocation_result" {
  description = "Result returned by invoking the Lambda function."
  value       = data.aws_lambda_invocation.example_lambda_invocation.result
}