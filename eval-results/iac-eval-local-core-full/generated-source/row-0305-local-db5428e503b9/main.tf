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

data "aws_caller_identity" "current" {}

data "archive_file" "caas_get" {
  type        = "zip"
  source_file = "${path.module}/lambda/get_cat.py"
  output_path = "${path.module}/build/get_cat.zip"
}

data "archive_file" "caas_put" {
  type        = "zip"
  source_file = "${path.module}/lambda/put_cat.py"
  output_path = "${path.module}/build/put_cat.zip"
}

resource "aws_s3_bucket" "cat_pictures" {
  bucket_prefix = "caas-cat-pictures-"
}

resource "aws_dynamodb_table" "cats" {
  name         = "caas-cats"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "name"

  attribute {
    name = "name"
    type = "S"
  }
}

resource "aws_iam_role" "caas_get" {
  name_prefix = "caas-get-lambda-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role" "caas_put" {
  name_prefix = "caas-put-lambda-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "caas_get" {
  name = "caas-get-lambda-access"
  role = aws_iam_role.caas_get.id

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
        Resource = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*"
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
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.cats.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "caas_put" {
  name = "caas-put-lambda-access"
  role = aws_iam_role.caas_put.id

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
        Resource = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
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
          "dynamodb:PutItem",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.cats.arn
      }
    ]
  })
}

resource "aws_lambda_function" "caas_get" {
  function_name    = "caas_get"
  role             = aws_iam_role.caas_get.arn
  handler          = "get_cat.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.caas_get.output_path
  source_code_hash = data.archive_file.caas_get.output_base64sha256

  environment {
    variables = {
      CAT_BUCKET = aws_s3_bucket.cat_pictures.bucket
      CAT_TABLE  = aws_dynamodb_table.cats.name
    }
  }
}

resource "aws_lambda_function" "caas_put" {
  function_name    = "caas_put"
  role             = aws_iam_role.caas_put.arn
  handler          = "put_cat.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.caas_put.output_path
  source_code_hash = data.archive_file.caas_put.output_base64sha256

  environment {
    variables = {
      CAT_BUCKET = aws_s3_bucket.cat_pictures.bucket
      CAT_TABLE  = aws_dynamodb_table.cats.name
    }
  }
}

resource "aws_api_gateway_rest_api" "caas" {
  name = "caas"
}

resource "aws_api_gateway_resource" "caas_cat" {
  rest_api_id = aws_api_gateway_rest_api.caas.id
  parent_id   = aws_api_gateway_rest_api.caas.root_resource_id
  path_part   = "cat"
}

resource "aws_api_gateway_method" "caas_get" {
  rest_api_id   = aws_api_gateway_rest_api.caas.id
  resource_id   = aws_api_gateway_resource.caas_cat.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "caas_put" {
  rest_api_id   = aws_api_gateway_rest_api.caas.id
  resource_id   = aws_api_gateway_resource.caas_cat.id
  http_method   = "PUT"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "caas_get" {
  rest_api_id             = aws_api_gateway_rest_api.caas.id
  resource_id             = aws_api_gateway_resource.caas_cat.id
  http_method             = aws_api_gateway_method.caas_get.http_method
  integration_http_method = "GET"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.caas_get.invoke_arn
}

resource "aws_api_gateway_integration" "caas_put" {
  rest_api_id             = aws_api_gateway_rest_api.caas.id
  resource_id             = aws_api_gateway_resource.caas_cat.id
  http_method             = aws_api_gateway_method.caas_put.http_method
  integration_http_method = "PUT"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.caas_put.invoke_arn
}

resource "aws_lambda_permission" "caas_get" {
  statement_id  = "AllowCaasGetApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.caas_get.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.caas.execution_arn}/*/${aws_api_gateway_method.caas_get.http_method}${aws_api_gateway_resource.caas_cat.path}"
}

resource "aws_lambda_permission" "caas_put" {
  statement_id  = "AllowCaasPutApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.caas_put.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.caas.execution_arn}/*/${aws_api_gateway_method.caas_put.http_method}${aws_api_gateway_resource.caas_cat.path}"
}
