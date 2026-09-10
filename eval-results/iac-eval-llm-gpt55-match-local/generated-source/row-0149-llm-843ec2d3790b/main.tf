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
  region = "us-east-1"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function."
  type        = string
  default     = "nodejs18-example-lambda"
}

variable "lambda_handler" {
  description = "Handler for the Lambda function."
  type        = string
  default     = "lambda.handler"
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function."
  type        = string
  default     = "nodejs18.x"
}

resource "local_file" "lambda_source" {
  filename = "${path.module}/lambda.js"

  content = <<EOF
exports.handler = async (event) => {
  console.log("Received event:", JSON.stringify(event, null, 2));

  return {
    statusCode: 200,
    body: JSON.stringify({
      message: "Hello from AWS Lambda using Node.js 18!",
      input: event
    })
  };
};
EOF
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_source.filename
  output_path = "${path.module}/lambda_function.zip"

  depends_on = [
    local_file.lambda_source
  ]
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole"
    ]
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.lambda_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "lambda_function" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_role.arn
  handler       = var.lambda_handler
  runtime       = var.lambda_runtime

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]
}

output "lambda_function_name" {
  description = "The name of the created Lambda function."
  value       = aws_lambda_function.lambda_function.function_name
}

output "lambda_function_arn" {
  description = "The ARN of the created Lambda function."
  value       = aws_lambda_function.lambda_function.arn
}

output "lambda_role_arn" {
  description = "The ARN of the IAM role used by the Lambda function."
  value       = aws_iam_role.lambda_role.arn
}