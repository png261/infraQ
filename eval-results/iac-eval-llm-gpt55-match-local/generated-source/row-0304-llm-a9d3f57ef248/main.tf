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
  type        = string
  description = "AWS region to deploy resources into."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Name prefix for project resources."
  default     = "cat-picture-service"
}

variable "lambda_runtime" {
  type        = string
  description = "Lambda runtime."
  default     = "python3.12"
}

resource "random_id" "suffix" {
  byte_length = 4
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "cat_pictures" {
  bucket        = "${var.project_name}-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "cat_pictures" {
  bucket = aws_s3_bucket.cat_pictures.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cat_pictures" {
  bucket = aws_s3_bucket.cat_pictures.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_dynamodb_table" "cat_pictures" {
  name         = "${var.project_name}-metadata-${random_id.suffix.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "cat_id"

  attribute {
    name = "cat_id"
    type = "S"
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-role-${random_id.suffix.hex}"

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
  name = "${var.project_name}-lambda-policy-${random_id.suffix.hex}"
  role = aws_iam_role.lambda_execution_role.id

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
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.cat_pictures.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.cat_pictures.arn
      }
    ]
  })
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/cat_service_lambda.zip"

  source {
    filename = "index.py"
    content  = <<PYTHON
import base64
import boto3
import json
import os
import random
import time
import uuid

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

BUCKET_NAME = os.environ["BUCKET_NAME"]
TABLE_NAME = os.environ["TABLE_NAME"]

table = dynamodb.Table(TABLE_NAME)

def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type"
        },
        "body": json.dumps(body)
    }

def lambda_handler(event, context):
    method = event.get("httpMethod", "")

    if method == "OPTIONS":
        return response(200, {"message": "CORS preflight successful"})

    if method == "POST":
        body = event.get("body")

        if not body:
            return response(400, {"error": "Request body must contain cat picture data"})

        is_base64 = event.get("isBase64Encoded", False)

        if is_base64:
            image_bytes = base64.b64decode(body)
        else:
            image_bytes = body.encode("utf-8")

        cat_id = str(uuid.uuid4())
        object_key = f"cats/{cat_id}.jpg"

        content_type = "image/jpeg"
        headers = event.get("headers") or {}

        for key, value in headers.items():
            if key.lower() == "content-type":
                content_type = value
                break

        s3.put_object(
            Bucket=BUCKET_NAME,
            Key=object_key,
            Body=image_bytes,
            ContentType=content_type
        )

        table.put_item(
            Item={
                "cat_id": cat_id,
                "s3_key": object_key,
                "bucket": BUCKET_NAME,
                "content_type": content_type,
                "created_at": int(time.time())
            }
        )

        return response(201, {
            "message": "Cat picture uploaded successfully",
            "cat_id": cat_id,
            "s3_key": object_key
        })

    if method == "GET":
        scan_result = table.scan()
        items = scan_result.get("Items", [])

        while "LastEvaluatedKey" in scan_result:
            scan_result = table.scan(ExclusiveStartKey=scan_result["LastEvaluatedKey"])
            items.extend(scan_result.get("Items", []))

        if not items:
            return response(404, {"error": "No cat pictures have been uploaded yet"})

        cat = random.choice(items)

        presigned_url = s3.generate_presigned_url(
            ClientMethod="get_object",
            Params={
                "Bucket": cat["bucket"],
                "Key": cat["s3_key"]
            },
            ExpiresIn=3600
        )

        return response(200, {
            "cat_id": cat["cat_id"],
            "s3_key": cat["s3_key"],
            "url": presigned_url,
            "expires_in_seconds": 3600
        })

    return response(405, {"error": f"Method {method} is not allowed"})
PYTHON
  }
}

resource "aws_lambda_function" "cat_service" {
  function_name = "${var.project_name}-lambda-${random_id.suffix.hex}"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "index.lambda_handler"
  runtime       = var.lambda_runtime

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = 30
  memory_size = 256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cat_pictures.bucket
      TABLE_NAME  = aws_dynamodb_table.cat_pictures.name
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy
  ]
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.cat_service.function_name}"
  retention_in_days = 14
}

resource "aws_api_gateway_rest_api" "cat_api" {
  name        = "${var.project_name}-api-${random_id.suffix.hex}"
  description = "REST API for uploading cat pictures and retrieving random cat pictures."

  binary_media_types = [
    "image/jpeg",
    "image/png",
    "image/gif",
    "application/octet-stream"
  ]

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "cats" {
  rest_api_id = aws_api_gateway_rest_api.cat_api.id
  parent_id   = aws_api_gateway_rest_api.cat_api.root_resource_id
  path_part   = "cats"
}

resource "aws_api_gateway_method" "cats_any" {
  rest_api_id   = aws_api_gateway_rest_api.cat_api.id
  resource_id   = aws_api_gateway_resource.cats.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "cats_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.cat_api.id
  resource_id             = aws_api_gateway_resource.cats.id
  http_method             = aws_api_gateway_method.cats_any.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.cat_service.invoke_arn
}

resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cat_service.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.cat_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "cat_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.cat_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.cats.id,
      aws_api_gateway_method.cats_any.id,
      aws_api_gateway_integration.cats_lambda.id
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.cats_lambda,
    aws_lambda_permission.allow_api_gateway
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.cat_api.id
  deployment_id = aws_api_gateway_deployment.cat_api_deployment.id
  stage_name    = "prod"
}

output "api_base_url" {
  description = "Base URL for the deployed API Gateway stage."
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "cats_endpoint" {
  description = "Endpoint for uploading and retrieving cat pictures."
  value       = "${aws_api_gateway_stage.prod.invoke_url}/cats"
}

output "s3_bucket_name" {
  description = "S3 bucket storing uploaded cat pictures."
  value       = aws_s3_bucket.cat_pictures.bucket
}

output "dynamodb_table_name" {
  description = "DynamoDB table storing cat picture metadata."
  value       = aws_dynamodb_table.cat_pictures.name
}