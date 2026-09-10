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
  description = "AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming."
  type        = string
  default     = "cat-picture-service"
}

variable "lambda_runtime" {
  description = "Lambda runtime."
  type        = string
  default     = "python3.12"
}

variable "presigned_url_expiration_seconds" {
  description = "Expiration time for random cat picture pre-signed URLs."
  type        = number
  default     = 3600
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_prefix = "${var.project_name}-${random_id.suffix.hex}"
  bucket_name = "${var.project_name}-${random_id.suffix.hex}"
}

resource "aws_s3_bucket" "cat_pictures" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = {
    Name        = local.bucket_name
    Application = var.project_name
  }
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

resource "aws_s3_bucket_versioning" "cat_pictures" {
  bucket = aws_s3_bucket.cat_pictures.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "archive_file" "lambda_package" {
  type        = "zip"
  output_path = "${path.module}/cat_service_lambda.zip"

  source {
    filename = "index.py"

    content = <<PYTHON
import base64
import json
import mimetypes
import os
import random
import time
import uuid

import boto3

s3 = boto3.client("s3")

BUCKET_NAME = os.environ["BUCKET_NAME"]
PRESIGNED_URL_EXPIRATION_SECONDS = int(os.environ.get("PRESIGNED_URL_EXPIRATION_SECONDS", "3600"))


def response(status_code, body, headers=None):
    base_headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type"
    }

    if headers:
        base_headers.update(headers)

    return {
        "statusCode": status_code,
        "headers": base_headers,
        "body": json.dumps(body)
    }


def extension_from_content_type(content_type):
    if not content_type:
        return ".jpg"

    guessed = mimetypes.guess_extension(content_type.split(";")[0].strip())

    if guessed:
        return guessed

    return ".jpg"


def upload_cat_picture(event):
    body = event.get("body")

    if not body:
        return response(400, {
            "message": "Request body is required. Send image bytes in the POST body."
        })

    is_base64_encoded = event.get("isBase64Encoded", False)

    try:
        if is_base64_encoded:
            image_bytes = base64.b64decode(body)
        else:
            image_bytes = body.encode("utf-8")
    except Exception as exc:
        return response(400, {
            "message": "Could not decode uploaded image.",
            "error": str(exc)
        })

    if len(image_bytes) == 0:
        return response(400, {
            "message": "Uploaded image was empty."
        })

    headers = event.get("headers") or {}
    normalized_headers = {k.lower(): v for k, v in headers.items()}
    content_type = normalized_headers.get("content-type", "image/jpeg")

    if not content_type.startswith("image/"):
        return response(400, {
            "message": "Only image uploads are allowed.",
            "received_content_type": content_type
        })

    extension = extension_from_content_type(content_type)
    object_key = f"cats/{int(time.time())}-{uuid.uuid4()}{extension}"

    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=object_key,
        Body=image_bytes,
        ContentType=content_type,
        ServerSideEncryption="AES256"
    )

    presigned_url = s3.generate_presigned_url(
        ClientMethod="get_object",
        Params={
            "Bucket": BUCKET_NAME,
            "Key": object_key
        },
        ExpiresIn=PRESIGNED_URL_EXPIRATION_SECONDS
    )

    return response(201, {
        "message": "Cat picture uploaded successfully.",
        "bucket": BUCKET_NAME,
        "key": object_key,
        "url": presigned_url,
        "url_expires_in_seconds": PRESIGNED_URL_EXPIRATION_SECONDS
    })


def get_random_cat_picture():
    paginator = s3.get_paginator("list_objects_v2")

    keys = []

    for page in paginator.paginate(Bucket=BUCKET_NAME, Prefix="cats/"):
        for item in page.get("Contents", []):
            key = item.get("Key")
            if key and not key.endswith("/"):
                keys.append(key)

    if not keys:
        return response(404, {
            "message": "No cat pictures have been uploaded yet."
        })

    selected_key = random.choice(keys)

    presigned_url = s3.generate_presigned_url(
        ClientMethod="get_object",
        Params={
            "Bucket": BUCKET_NAME,
            "Key": selected_key
        },
        ExpiresIn=PRESIGNED_URL_EXPIRATION_SECONDS
    )

    return response(200, {
        "message": "Random cat picture selected.",
        "bucket": BUCKET_NAME,
        "key": selected_key,
        "url": presigned_url,
        "url_expires_in_seconds": PRESIGNED_URL_EXPIRATION_SECONDS
    })


def lambda_handler(event, context):
    method = (
        event.get("httpMethod")
        or event.get("requestContext", {}).get("http", {}).get("method")
        or ""
    ).upper()

    if method == "OPTIONS":
        return response(200, {
            "message": "CORS preflight successful."
        })

    if method == "POST":
        return upload_cat_picture(event)

    if method == "GET":
        return get_random_cat_picture()

    return response(405, {
        "message": f"Method {method} is not allowed. Use GET or POST."
    })
PYTHON
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role"

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

  tags = {
    Name        = "${local.name_prefix}-lambda-role"
    Application = var.project_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${local.name_prefix}-lambda-policy"
  description = "Allows Lambda to manage cat pictures in S3 and write logs."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaLogging"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowCatBucketList"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.cat_pictures.arn
      },
      {
        Sid    = "AllowCatObjectReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.cat_pictures.arn}/cats/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-handler"
  retention_in_days = 14

  tags = {
    Name        = "${local.name_prefix}-lambda-logs"
    Application = var.project_name
  }
}

resource "aws_lambda_function" "cat_service" {
  function_name = "${local.name_prefix}-handler"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.lambda_handler"
  runtime       = var.lambda_runtime

  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  timeout     = 30
  memory_size = 256

  environment {
    variables = {
      BUCKET_NAME                       = aws_s3_bucket.cat_pictures.bucket
      PRESIGNED_URL_EXPIRATION_SECONDS = tostring(var.presigned_url_expiration_seconds)
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_policy_attachment,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = {
    Name        = "${local.name_prefix}-handler"
    Application = var.project_name
  }
}

resource "aws_api_gateway_rest_api" "cat_api" {
  name        = "${local.name_prefix}-api"
  description = "API for uploading cat pictures and retrieving a random cat picture."

  binary_media_types = [
    "*/*"
  ]

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${local.name_prefix}-api"
    Application = var.project_name
  }
}

resource "aws_api_gateway_resource" "cats" {
  rest_api_id = aws_api_gateway_rest_api.cat_api.id
  parent_id   = aws_api_gateway_rest_api.cat_api.root_resource_id
  path_part   = "cats"
}

resource "aws_api_gateway_method" "get_cats" {
  rest_api_id   = aws_api_gateway_rest_api.cat_api.id
  resource_id   = aws_api_gateway_resource.cats.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "post_cats" {
  rest_api_id   = aws_api_gateway_rest_api.cat_api.id
  resource_id   = aws_api_gateway_resource.cats.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "options_cats" {
  rest_api_id   = aws_api_gateway_rest_api.cat_api.id
  resource_id   = aws_api_gateway_resource.cats.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_cats_lambda" {
  rest_api_id = aws_api_gateway_rest_api.cat_api.id
  resource_id = aws_api_gateway_resource.cats.id
  http_method = aws_api_gateway_method.get_cats.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.cat_service.invoke_arn
}

resource "aws_api_gateway_integration" "post_cats_lambda" {
  rest_api_id = aws_api_gateway_rest_api.cat_api.id
  resource_id = aws_api_gateway_resource.cats.id
  http_method = aws_api_gateway_method.post_cats.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.cat_service.invoke_arn

  content_handling = "CONVERT_TO_TEXT"
}

resource "aws_api_gateway_integration" "options_cats_lambda" {
  rest_api_id = aws_api_gateway_rest_api.cat_api.id
  resource_id = aws_api_gateway_resource.cats.id
  http_method = aws_api_gateway_method.options_cats.http_method

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
      aws_api_gateway_method.get_cats.id,
      aws_api_gateway_method.post_cats.id,
      aws_api_gateway_method.options_cats.id,
      aws_api_gateway_integration.get_cats_lambda.id,
      aws_api_gateway_integration.post_cats_lambda.id,
      aws_api_gateway_integration.options_cats_lambda.id,
      data.archive_file.lambda_package.output_base64sha256
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.get_cats_lambda,
    aws_api_gateway_integration.post_cats_lambda,
    aws_api_gateway_integration.options_cats_lambda,
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

  tags = {
    Name        = "${local.name_prefix}-prod-stage"
    Application = var.project_name
  }
}

output "api_base_url" {
  description = "Base URL of the deployed API Gateway stage."
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "cat_pictures_endpoint" {
  description = "Endpoint for uploading and retrieving cat pictures."
  value       = "${aws_api_gateway_stage.prod.invoke_url}/cats"
}

output "upload_example" {
  description = "Example curl command to upload a cat picture."
  value       = "curl -X POST -H 'Content-Type: image/jpeg' --data-binary '@/path/to/cat.jpg' '${aws_api_gateway_stage.prod.invoke_url}/cats'"
}

output "random_cat_example" {
  description = "Example curl command to retrieve a random cat picture pre-signed URL."
  value       = "curl '${aws_api_gateway_stage.prod.invoke_url}/cats'"
}

output "s3_bucket_name" {
  description = "S3 bucket storing cat pictures."
  value       = aws_s3_bucket.cat_pictures.bucket
}