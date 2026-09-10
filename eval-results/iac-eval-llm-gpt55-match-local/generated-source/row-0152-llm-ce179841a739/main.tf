terraform {
  required_version = ">= 1.3.0"

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

variable "lambda_function_name" {
  description = "Name of the Lambda function."
  type        = string
  default     = "example-lambda-function"
}

variable "lambda_alias_name" {
  description = "Name of the Lambda alias."
  type        = string
  default     = "live"
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function."
  type        = string
  default     = "python3.12"
}

variable "lambda_handler" {
  description = "Handler for the Lambda function."
  type        = string
  default     = "index.lambda_handler"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    filename = "index.py"
    content  = <<EOF
import json

def lambda_handler(event, context):
    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Hello from Lambda alias!"
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

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "example" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = var.lambda_handler
  runtime       = var.lambda_runtime

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  publish = true

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]
}

resource "aws_lambda_alias" "example_alias" {
  name             = var.lambda_alias_name
  description      = "Alias for the published Lambda function version"
  function_name    = aws_lambda_function.example.function_name
  function_version = aws_lambda_function.example.version
}

output "lambda_function_name" {
  description = "The name of the Lambda function."
  value       = aws_lambda_function.example.function_name
}

output "lambda_function_arn" {
  description = "The ARN of the Lambda function."
  value       = aws_lambda_function.example.arn
}

output "lambda_version" {
  description = "The published version of the Lambda function."
  value       = aws_lambda_function.example.version
}

output "lambda_alias_name" {
  description = "The name of the Lambda alias."
  value       = aws_lambda_alias.example_alias.name
}

output "lambda_alias_arn" {
  description = "The ARN of the Lambda alias."
  value       = aws_lambda_alias.example_alias.arn
}