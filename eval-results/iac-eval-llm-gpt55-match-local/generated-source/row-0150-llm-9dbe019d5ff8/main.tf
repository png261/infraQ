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

locals {
  lambda_source = <<-PY
    import json

    def handler(event, context):
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json"
            },
            "body": json.dumps({
                "message": "Hello from example_lambda!"
            })
        }
  PY
}

resource "local_file" "lambda_python_file" {
  filename = "${path.module}/lambda_function.py"
  content  = local.lambda_source
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_python_file.filename
  output_path = "${path.module}/example_lambda.zip"

  depends_on = [
    local_file.lambda_python_file
  ]
}

resource "aws_iam_role" "lambda_execution_role" {
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

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "example_lambda" {
  function_name = "example_lambda"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.handler"
  runtime       = "python3.12"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]
}

resource "aws_lambda_function_url" "example_lambda_url" {
  function_name      = aws_lambda_function.example_lambda.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST"]
    allow_headers     = ["*"]
    expose_headers    = []
    max_age           = 86400
  }
}

resource "aws_lambda_permission" "allow_public_function_url_invocation" {
  statement_id           = "AllowPublicFunctionUrlInvocation"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.example_lambda.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

output "example_lambda_function_name" {
  value = aws_lambda_function.example_lambda.function_name
}

output "example_lambda_function_url" {
  value = aws_lambda_function_url.example_lambda_url.function_url
}