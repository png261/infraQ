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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function."
  type        = string
  default     = "dynamodb-stream-processor"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  type        = string
  default     = "lambda-event-source-demo-table"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    filename = "index.py"
    content  = <<EOF
import json

def handler(event, context):
    print("Received DynamoDB stream event:")
    print(json.dumps(event))

    for record in event.get("Records", []):
        event_name = record.get("eventName")
        dynamodb_record = record.get("dynamodb", {})
        print(f"Event: {event_name}")
        print(json.dumps(dynamodb_record))

    return {
        "statusCode": 200,
        "body": "Processed DynamoDB stream records"
    }
EOF
  }
}

resource "aws_dynamodb_table" "example" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = {
    Name        = var.dynamodb_table_name
    Environment = "demo"
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

resource "aws_iam_policy" "lambda_dynamodb_stream_policy" {
  name        = "${var.lambda_function_name}-dynamodb-stream-policy"
  description = "Allows Lambda to read from DynamoDB Streams and write logs to CloudWatch."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams"
        ]
        Resource = aws_dynamodb_table.example.stream_arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.lambda_function_name}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_stream_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_stream_policy.arn
}

resource "aws_lambda_function" "processor" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_execution_role.arn

  runtime = "python3.12"
  handler = "index.handler"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = 30
  memory_size = 128

  depends_on = [
    aws_iam_role_policy_attachment.lambda_dynamodb_stream_attachment
  ]

  tags = {
    Name        = var.lambda_function_name
    Environment = "demo"
  }
}

resource "aws_lambda_event_source_mapping" "dynamodb_stream_mapping" {
  event_source_arn  = aws_dynamodb_table.example.stream_arn
  function_name     = aws_lambda_function.processor.arn
  starting_position = "LATEST"

  batch_size                         = 100
  maximum_batching_window_in_seconds = 5
  enabled                            = true

  depends_on = [
    aws_lambda_function.processor,
    aws_dynamodb_table.example
  ]
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  value       = aws_dynamodb_table.example.name
}

output "dynamodb_stream_arn" {
  description = "ARN of the DynamoDB stream."
  value       = aws_dynamodb_table.example.stream_arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function."
  value       = aws_lambda_function.processor.function_name
}

output "lambda_event_source_mapping_uuid" {
  description = "UUID of the Lambda event source mapping."
  value       = aws_lambda_event_source_mapping.dynamodb_stream_mapping.uuid
}