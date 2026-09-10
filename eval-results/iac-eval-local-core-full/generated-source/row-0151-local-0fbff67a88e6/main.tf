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
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "example_lambda" {
  name               = "example_lambda_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "archive_file" "example_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/example_lambda.zip"
}

resource "aws_lambda_function" "example_lambda" {
  function_name    = "example_lambda"
  role             = aws_iam_role.example_lambda.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.example_lambda.output_path
  source_code_hash = data.archive_file.example_lambda.output_base64sha256
}

resource "aws_lambda_invocation" "example_lambda" {
  function_name = aws_lambda_function.example_lambda.function_name

  input = jsonencode({
    message = "invoke example_lambda"
  })
}

output "example_lambda_function_name" {
  value = aws_lambda_function.example_lambda.function_name
}

output "example_lambda_invocation_result" {
  value = aws_lambda_invocation.example_lambda.result
}
