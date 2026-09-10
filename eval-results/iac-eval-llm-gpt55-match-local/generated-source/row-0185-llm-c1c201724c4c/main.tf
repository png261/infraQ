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

    local = {
      source  = "hashicorp/local"
      version = ">= 2.4"
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
  default     = "nodejs18-example-lambda"
}

locals {
  lambda_source_code = <<-EOT
    exports.handler = async (event) => {
      console.log("Received event:", JSON.stringify(event, null, 2));

      return {
        statusCode: 200,
        body: JSON.stringify({
          message: "Hello from AWS Lambda running on Node.js 18!",
          input: event
        })
      };
    };
  EOT
}

resource "local_file" "lambda_js_source" {
  filename = "${path.module}/lambda.js"
  content  = local.lambda_source_code
}

resource "local_file" "index_js_handler" {
  filename = "${path.module}/index.js"
  content  = local.lambda_source_code

  depends_on = [
    local_file.lambda_js_source
  ]
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.index_js_handler.filename
  output_path = "${path.module}/lambda_function.zip"

  depends_on = [
    local_file.index_js_handler
  ]
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

resource "aws_lambda_function" "nodejs18_lambda" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_execution_role.arn

  runtime = "nodejs18.x"
  handler = "index.handler"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]
}

output "lambda_function_name" {
  description = "Name of the deployed Lambda function."
  value       = aws_lambda_function.nodejs18_lambda.function_name
}

output "lambda_function_arn" {
  description = "ARN of the deployed Lambda function."
  value       = aws_lambda_function.nodejs18_lambda.arn
}