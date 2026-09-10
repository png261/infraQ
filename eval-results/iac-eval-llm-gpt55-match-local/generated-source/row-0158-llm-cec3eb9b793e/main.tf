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
  description = "AWS region where the Lambda function will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function."
  type        = string
  default     = "lambda-js-function"
}

variable "lambda_runtime" {
  description = "Node.js runtime for the Lambda function."
  type        = string
  default     = "nodejs20.x"
}

variable "lambda_handler" {
  description = "Lambda function handler. For lambda.js exporting handler, use lambda.handler."
  type        = string
  default     = "lambda.handler"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda.js"
  output_path = "${path.module}/lambda.zip"
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

resource "aws_lambda_function" "lambda_js_function" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_execution_role.arn

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  handler = var.lambda_handler
  runtime = var.lambda_runtime

  timeout     = 30
  memory_size = 128

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]
}

output "lambda_function_name" {
  description = "The name of the deployed Lambda function."
  value       = aws_lambda_function.lambda_js_function.function_name
}

output "lambda_function_arn" {
  description = "The ARN of the deployed Lambda function."
  value       = aws_lambda_function.lambda_js_function.arn
}