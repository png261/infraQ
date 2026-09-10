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

data "archive_file" "test_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/test_lambda.zip"
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

resource "aws_iam_role" "test_lambda" {
  name               = "test-lambda-execution-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.test_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "test_lambda" {
  function_name    = "test_lambda"
  role             = aws_iam_role.test_lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.test_lambda.output_path
  source_code_hash = data.archive_file.test_lambda.output_base64sha256

  depends_on = [aws_iam_role_policy_attachment.lambda_basic_execution]
}

resource "aws_cloudwatch_event_rule" "ec2_image_created" {
  name        = "ec2-image-created"
  description = "Trigger test_lambda whenever an EC2 AMI creation API call succeeds."

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["ec2.amazonaws.com"]
      eventName   = ["CreateImage"]
      errorCode = [{
        exists = false
      }]
    }
  })
}

resource "aws_cloudwatch_event_target" "test_lambda" {
  rule      = aws_cloudwatch_event_rule.ec2_image_created.name
  target_id = "test-lambda"
  arn       = aws_lambda_function.test_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridgeEc2ImageCreated"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.test_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_image_created.arn
}
