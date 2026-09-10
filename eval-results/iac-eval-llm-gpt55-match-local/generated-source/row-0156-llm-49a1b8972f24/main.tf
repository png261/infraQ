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

locals {
  lambda_source_dir = "${path.module}/lambda_src"
  lambda_zip_path   = "${path.module}/test_lambda.zip"
}

resource "local_file" "lambda_index" {
  filename = "${local.lambda_source_dir}/index.py"

  content = <<EOF
import json

def lambda_handler(event, context):
    print("EC2 image creation event received:")
    print(json.dumps(event))
    
    image_id = event.get("detail", {}).get("responseElements", {}).get("imageId")
    
    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "CreateImage event processed",
            "imageId": image_id
        })
    }
EOF
}

data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = local.lambda_source_dir
  output_path = local.lambda_zip_path

  depends_on = [
    local_file.lambda_index
  ]
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "test_lambda_execution_role"

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

resource "aws_lambda_function" "test_lambda" {
  function_name = "test_lambda"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]
}

resource "aws_cloudwatch_event_rule" "ec2_create_image_rule" {
  name        = "trigger-test-lambda-on-ec2-image-created"
  description = "Triggers test_lambda whenever an EC2 AMI is created using the CreateImage API."

  event_pattern = jsonencode({
    source = [
      "aws.ec2"
    ]
    detail-type = [
      "AWS API Call via CloudTrail"
    ]
    detail = {
      eventSource = [
        "ec2.amazonaws.com"
      ]
      eventName = [
        "CreateImage"
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.ec2_create_image_rule.name
  target_id = "test-lambda-target"
  arn       = aws_lambda_function.test_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge_to_invoke_lambda" {
  statement_id  = "AllowExecutionFromEventBridgeCreateImage"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.test_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_create_image_rule.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function triggered by EC2 CreateImage events."
  value       = aws_lambda_function.test_lambda.function_name
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule listening for EC2 CreateImage events."
  value       = aws_cloudwatch_event_rule.ec2_create_image_rule.name
}