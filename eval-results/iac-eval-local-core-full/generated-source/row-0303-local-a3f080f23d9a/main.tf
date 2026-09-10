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
  name_prefix = "cat-pictures"
}

resource "aws_s3_bucket" "cat_pictures" {
  bucket_prefix = "${local.name_prefix}-"
}

resource "aws_dynamodb_table" "cat_metadata" {
  name         = "${local.name_prefix}-metadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "cat_id"

  attribute {
    name = "cat_id"
    type = "S"
  }
}

resource "aws_iam_role" "upload_lambda" {
  name_prefix = "${local.name_prefix}-upload-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role" "random_lambda" {
  name_prefix = "${local.name_prefix}-random-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "upload_lambda" {
  name = "${local.name_prefix}-upload-policy"
  role = aws_iam_role.upload_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.cat_pictures.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.cat_metadata.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "random_lambda" {
  name = "${local.name_prefix}-random-policy"
  role = aws_iam_role.random_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.cat_pictures.arn,
          "${aws_s3_bucket.cat_pictures.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.cat_metadata.arn
      }
    ]
  })
}

data "archive_file" "upload_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/upload_cat.py"
  output_path = "${path.module}/build/upload_cat.zip"
}

data "archive_file" "random_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/random_cat.py"
  output_path = "${path.module}/build/random_cat.zip"
}

resource "aws_lambda_function" "upload_cat" {
  function_name    = "${local.name_prefix}-upload"
  role             = aws_iam_role.upload_lambda.arn
  handler          = "upload_cat.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.upload_lambda.output_path
  source_code_hash = data.archive_file.upload_lambda.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cat_pictures.bucket
      TABLE_NAME  = aws_dynamodb_table.cat_metadata.name
    }
  }

  depends_on = [aws_iam_role_policy.upload_lambda]
}

resource "aws_lambda_function" "random_cat" {
  function_name    = "${local.name_prefix}-random"
  role             = aws_iam_role.random_lambda.arn
  handler          = "random_cat.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.random_lambda.output_path
  source_code_hash = data.archive_file.random_lambda.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cat_pictures.bucket
      TABLE_NAME  = aws_dynamodb_table.cat_metadata.name
    }
  }

  depends_on = [aws_iam_role_policy.random_lambda]
}

resource "aws_api_gateway_rest_api" "cat_api" {
  name = "${local.name_prefix}-api"
}

resource "aws_api_gateway_resource" "cats" {
  rest_api_id = aws_api_gateway_rest_api.cat_api.id
  parent_id   = aws_api_gateway_rest_api.cat_api.root_resource_id
  path_part   = "cats"
}

resource "aws_api_gateway_method" "get_cat" {
  rest_api_id   = aws_api_gateway_rest_api.cat_api.id
  resource_id   = aws_api_gateway_resource.cats.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "put_cat" {
  rest_api_id   = aws_api_gateway_rest_api.cat_api.id
  resource_id   = aws_api_gateway_resource.cats.id
  http_method   = "PUT"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_cat" {
  rest_api_id             = aws_api_gateway_rest_api.cat_api.id
  resource_id             = aws_api_gateway_resource.cats.id
  http_method             = aws_api_gateway_method.get_cat.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.random_cat.invoke_arn
}

resource "aws_api_gateway_integration" "put_cat" {
  rest_api_id             = aws_api_gateway_rest_api.cat_api.id
  resource_id             = aws_api_gateway_resource.cats.id
  http_method             = aws_api_gateway_method.put_cat.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.upload_cat.invoke_arn
}

resource "aws_api_gateway_deployment" "cat_api" {
  rest_api_id = aws_api_gateway_rest_api.cat_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.cats.id,
      aws_api_gateway_method.get_cat.id,
      aws_api_gateway_method.put_cat.id,
      aws_api_gateway_integration.get_cat.id,
      aws_api_gateway_integration.put_cat.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.get_cat,
    aws_api_gateway_integration.put_cat,
  ]
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.cat_api.id
  rest_api_id   = aws_api_gateway_rest_api.cat_api.id
  stage_name    = "prod"
}

resource "aws_lambda_permission" "allow_get_api" {
  statement_id  = "AllowExecutionFromAPIGatewayGet"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.random_cat.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.cat_api.execution_arn}/*/${aws_api_gateway_method.get_cat.http_method}${aws_api_gateway_resource.cats.path}"
}

resource "aws_lambda_permission" "allow_put_api" {
  statement_id  = "AllowExecutionFromAPIGatewayPut"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_cat.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.cat_api.execution_arn}/*/${aws_api_gateway_method.put_cat.http_method}${aws_api_gateway_resource.cats.path}"
}

output "api_resource_path" {
  value = aws_api_gateway_resource.cats.path
}

output "api_invoke_url" {
  value = "${aws_api_gateway_stage.prod.invoke_url}${aws_api_gateway_resource.cats.path}"
}

output "bucket_name" {
  value = aws_s3_bucket.cat_pictures.bucket
}
