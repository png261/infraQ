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

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

data "aws_caller_identity" "current" {}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "cat_pictures" {
  bucket        = "caas-cat-pictures-${random_id.bucket_suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "cat_pictures" {
  bucket = aws_s3_bucket.cat_pictures.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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

resource "aws_iam_role" "lambda_role" {
  name = "caas-lambda-role"

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

resource "aws_iam_role_policy" "lambda_policy" {
  name = "caas-lambda-policy"
  role = aws_iam_role.lambda_role.id

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
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
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
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.cats.arn
      }
    ]
  })
}

data "archive_file" "caas_get_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/caas_get_lambda.zip"

  source {
    filename = "index.py"
    content  = <<EOF
import json
import os
import boto3

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

BUCKET_NAME = os.environ["BUCKET_NAME"]
TABLE_NAME = os.environ["TABLE_NAME"]

def handler(event, context):
    table = dynamodb.Table(TABLE_NAME)

    name = None
    if event.get("queryStringParameters"):
        name = event["queryStringParameters"].get("name")

    if name:
        response = table.get_item(Key={"name": name})
        item = response.get("Item")
        if not item:
            return {
                "statusCode": 404,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"message": "Cat not found"})
            }

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(item)
        }

    response = table.scan()
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "cats": response.get("Items", []),
            "bucket": BUCKET_NAME
        })
    }
EOF
  }
}

data "archive_file" "caas_put_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/caas_put_lambda.zip"

  source {
    filename = "index.py"
    content  = <<EOF
import json
import os
import base64
import boto3

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

BUCKET_NAME = os.environ["BUCKET_NAME"]
TABLE_NAME = os.environ["TABLE_NAME"]

def handler(event, context):
    table = dynamodb.Table(TABLE_NAME)

    body = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")

    try:
        payload = json.loads(body)
    except Exception:
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": "Invalid JSON body"})
        }

    name = payload.get("name")
    if not name:
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": "Field 'name' is required"})
        }

    item = {"name": name}

    if "description" in payload:
        item["description"] = payload["description"]

    if "picture_base64" in payload:
        object_key = f"{name}.jpg"
        picture_bytes = base64.b64decode(payload["picture_base64"])
        s3.put_object(
            Bucket=BUCKET_NAME,
            Key=object_key,
            Body=picture_bytes,
            ContentType="image/jpeg"
        )
        item["picture_s3_key"] = object_key

    table.put_item(Item=item)

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": "Cat saved",
            "cat": item
        })
    }
EOF
  }
}

resource "aws_lambda_function" "caas_get" {
  function_name = "caas_get"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  filename      = data.archive_file.caas_get_lambda_zip.output_path

  source_code_hash = data.archive_file.caas_get_lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cat_pictures.bucket
      TABLE_NAME  = aws_dynamodb_table.cats.name
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy
  ]
}

resource "aws_lambda_function" "caas_put" {
  function_name = "caas_put"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  filename      = data.archive_file.caas_put_lambda_zip.output_path

  source_code_hash = data.archive_file.caas_put_lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cat_pictures.bucket
      TABLE_NAME  = aws_dynamodb_table.cats.name
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy
  ]
}

resource "aws_api_gateway_rest_api" "caas" {
  name = "caas"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
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
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.caas_get.invoke_arn
}

resource "aws_api_gateway_integration" "caas_put" {
  rest_api_id             = aws_api_gateway_rest_api.caas.id
  resource_id             = aws_api_gateway_resource.caas_cat.id
  http_method             = aws_api_gateway_method.caas_put.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.caas_put.invoke_arn
}

resource "aws_lambda_permission" "allow_apigateway_get" {
  statement_id  = "AllowAPIGatewayInvokeGet"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.caas_get.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.caas.execution_arn}/*/${aws_api_gateway_method.caas_get.http_method}${aws_api_gateway_resource.caas_cat.path}"
}

resource "aws_lambda_permission" "allow_apigateway_put" {
  statement_id  = "AllowAPIGatewayInvokePut"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.caas_put.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.caas.execution_arn}/*/${aws_api_gateway_method.caas_put.http_method}${aws_api_gateway_resource.caas_cat.path}"
}

resource "aws_api_gateway_deployment" "caas" {
  rest_api_id = aws_api_gateway_rest_api.caas.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.caas_cat.id,
      aws_api_gateway_method.caas_get.id,
      aws_api_gateway_method.caas_put.id,
      aws_api_gateway_integration.caas_get.id,
      aws_api_gateway_integration.caas_put.id
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.caas_get,
    aws_api_gateway_integration.caas_put,
    aws_lambda_permission.allow_apigateway_get,
    aws_lambda_permission.allow_apigateway_put
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "caas" {
  rest_api_id   = aws_api_gateway_rest_api.caas.id
  deployment_id = aws_api_gateway_deployment.caas.id
  stage_name    = "prod"
}

output "api_gateway_base_url" {
  value = "https://${aws_api_gateway_rest_api.caas.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.caas.stage_name}"
}

output "cat_endpoint" {
  value = "https://${aws_api_gateway_rest_api.caas.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.caas.stage_name}/cat"
}

output "cat_pictures_bucket_name" {
  value = aws_s3_bucket.cat_pictures.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.cats.name
}