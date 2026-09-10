terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_s3_bucket" "cat_pictures" {
  bucket_prefix = "cat-pictures-"
}

resource "aws_dynamodb_table" "cat_pictures" {
  name         = "cat-pictures-metadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "picture_id"

  attribute {
    name = "picture_id"
    type = "S"
  }
}

resource "aws_iam_role" "upload_lambda" {
  name = "cat-picture-upload-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "random_lambda" {
  name = "cat-picture-random-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "upload_lambda" {
  name = "cat-picture-upload-lambda-policy"
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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.cat_pictures.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.cat_pictures.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "random_lambda" {
  name = "cat-picture-random-lambda-policy"
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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
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
        Resource = aws_dynamodb_table.cat_pictures.arn
      }
    ]
  })
}

resource "aws_lambda_function" "upload_cat" {
  function_name = "cat-picture-upload"
  role          = aws_iam_role.upload_lambda.arn
  handler       = "upload.lambda_handler"
  runtime       = "python3.12"
  filename      = "lambda_upload.zip"

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cat_pictures.bucket
      TABLE_NAME  = aws_dynamodb_table.cat_pictures.name
    }
  }

  depends_on = [aws_iam_role_policy.upload_lambda]
}

resource "aws_lambda_function" "random_cat" {
  function_name = "cat-picture-random"
  role          = aws_iam_role.random_lambda.arn
  handler       = "random.lambda_handler"
  runtime       = "python3.12"
  filename      = "lambda_random.zip"

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cat_pictures.bucket
      TABLE_NAME  = aws_dynamodb_table.cat_pictures.name
    }
  }

  depends_on = [aws_iam_role_policy.random_lambda]
}

resource "aws_api_gateway_rest_api" "cat_api" {
  name = "cat-pictures-api"
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

resource "aws_lambda_permission" "allow_get_from_api_gateway" {
  statement_id  = "AllowGetExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.random_cat.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.cat_api.execution_arn}/*/${aws_api_gateway_method.get_cat.http_method}${aws_api_gateway_resource.cats.path}"
}

resource "aws_lambda_permission" "allow_put_from_api_gateway" {
  statement_id  = "AllowPutExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_cat.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.cat_api.execution_arn}/*/${aws_api_gateway_method.put_cat.http_method}${aws_api_gateway_resource.cats.path}"
}

resource "aws_api_gateway_deployment" "cat_api" {
  rest_api_id = aws_api_gateway_rest_api.cat_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.cats.id,
      aws_api_gateway_method.get_cat.id,
      aws_api_gateway_method.put_cat.id,
      aws_api_gateway_integration.get_cat.id,
      aws_api_gateway_integration.put_cat.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.get_cat,
    aws_api_gateway_integration.put_cat
  ]
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.cat_api.id
  rest_api_id   = aws_api_gateway_rest_api.cat_api.id
  stage_name    = "prod"
}

output "api_base_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "cat_resource_path" {
  value = aws_api_gateway_resource.cats.path
}
