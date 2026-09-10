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

locals {
  name_prefix = "iac-eval-lambda-alias"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/build/lambda_function.zip"
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

data "aws_iam_policy_document" "lambda_basic_execution" {
  statement {
    sid    = "WriteCloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["arn:aws:logs:us-east-1:*:*"]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${local.name_prefix}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  inline_policy {
    name   = "basic-execution"
    policy = data.aws_iam_policy_document.lambda_basic_execution.json
  }
}

resource "aws_dynamodb_table" "example" {
  name         = "${local.name_prefix}-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_lambda_function" "example" {
  function_name    = "${local.name_prefix}-function"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  publish          = true

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.example.name
    }
  }
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  description      = "Live alias for the published Lambda function version."
  function_name    = aws_lambda_function.example.function_name
  function_version = aws_lambda_function.example.version
}
