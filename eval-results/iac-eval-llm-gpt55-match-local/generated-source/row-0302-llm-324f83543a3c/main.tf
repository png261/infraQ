terraform {
  required_version = ">= 1.4.0"

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
  description = "Name prefix for all resources."
  type        = string
  default     = "cat-picture-service"
}

resource "random_id" "suffix" {
  byte_length = 4
}

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

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-${random_id.suffix.hex}"
  retention_in_days = 14
}

resource "aws_iam_role" "lambda_role" {
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
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda_logs.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.cat_pictures.arn
      },
      {
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

locals {
  lambda_source = <<EOF
import base64
import boto3
import html
import json
import mimetypes
import os
import random
import urllib.parse

s3 = boto3.client("s3")

BUCKET = os.environ["BUCKET_NAME"]
PREFIX = "cats/"

HTML_PAGE = """
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <title>Random Cat Picture Service</title>
  <style>
    body {
      font-family: Arial, sans-serif;
      max-width: 760px;
      margin: 40px auto;
      padding: 0 20px;
      background: #fafafa;
      color: #222;
    }
    h1 {
      color: #5b2c83;
    }
    .card {
      background: white;
      border: 1px solid #ddd;
      border-radius: 10px;
      padding: 20px;
      margin-top: 20px;
      box-shadow: 0 2px 8px rgba(0,0,0,0.06);
    }
    button {
      background: #5b2c83;
      color: white;
      border: 0;
      padding: 10px 14px;
      border-radius: 6px;
      cursor: pointer;
      margin-top: 10px;
    }
    button:hover {
      background: #7d3c98;
    }
    img {
      max-width: 100%;
      margin-top: 20px;
      border-radius: 10px;
      border: 1px solid #ddd;
    }
    #status {
      margin-top: 12px;
      font-weight: bold;
    }
  </style>
</head>
<body>
  <h1>Cat Picture Service</h1>
  <p>Upload cat pictures and ask the service for a random cat picture on demand.</p>

  <div class="card">
    <h2>Upload a cat picture</h2>
    <input id="fileInput" type="file" accept="image/*" />
    <br />
    <button onclick="uploadCat()">Upload Cat</button>
    <div id="status"></div>
  </div>

  <div class="card">
    <h2>Random cat picture</h2>
    <button onclick="getRandomCat()">Show Random Cat</button>
    <br />
    <img id="catImage" style="display:none;" />
  </div>

  <script>
    async function uploadCat() {
      const input = document.getElementById("fileInput");
      const status = document.getElementById("status");

      if (!input.files.length) {
        status.textContent = "Please choose an image file first.";
        return;
      }

      const file = input.files[0];
      const safeName = encodeURIComponent(file.name);

      status.textContent = "Uploading...";

      const response = await fetch("/upload/" + safeName, {
        method: "POST",
        headers: {
          "Content-Type": file.type || "application/octet-stream"
        },
        body: file
      });

      if (response.ok) {
        const result = await response.json();
        status.textContent = "Uploaded: " + result.filename;
      } else {
        const text = await response.text();
        status.textContent = "Upload failed: " + text;
      }
    }

    async function getRandomCat() {
      const img = document.getElementById("catImage");
      img.style.display = "none";
      img.src = "/random?cacheBust=" + Date.now();
      img.onload = () => {
        img.style.display = "block";
      };
      img.onerror = async () => {
        alert("No cat picture could be loaded. Upload one first.");
      };
    }
  </script>
</body>
</html>
"""

def response(status_code, body, content_type="application/json", is_base64=False):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": content_type,
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type"
        },
        "body": body,
        "isBase64Encoded": is_base64
    }

def handle_home():
    return response(200, HTML_PAGE, "text/html; charset=utf-8")

def handle_upload(event, path):
    encoded_name = path[len("/upload/"):]
    filename = urllib.parse.unquote(encoded_name).strip()

    if not filename:
        return response(400, json.dumps({"error": "Filename is required"}))

    filename = filename.replace("/", "_").replace("\\\\", "_")
    key = PREFIX + filename

    body = event.get("body") or ""
    if event.get("isBase64Encoded"):
        data = base64.b64decode(body)
    else:
        data = body.encode("utf-8")

    if not data:
        return response(400, json.dumps({"error": "Uploaded file was empty"}))

    content_type = event.get("headers", {}).get("content-type") or event.get("headers", {}).get("Content-Type")
    if not content_type:
        content_type = mimetypes.guess_type(filename)[0] or "application/octet-stream"

    s3.put_object(
        Bucket=BUCKET,
        Key=key,
        Body=data,
        ContentType=content_type
    )

    return response(200, json.dumps({
        "message": "Cat picture uploaded",
        "filename": filename,
        "s3_key": key
    }))

def handle_random():
    objects = []
    paginator = s3.get_paginator("list_objects_v2")

    for page in paginator.paginate(Bucket=BUCKET, Prefix=PREFIX):
        for item in page.get("Contents", []):
            key = item.get("Key")
            if key and not key.endswith("/"):
                objects.append(key)

    if not objects:
        return response(404, json.dumps({
            "error": "No cat pictures have been uploaded yet"
        }))

    key = random.choice(objects)
    obj = s3.get_object(Bucket=BUCKET, Key=key)

    data = obj["Body"].read()
    content_type = obj.get("ContentType") or mimetypes.guess_type(key)[0] or "application/octet-stream"

    return response(
        200,
        base64.b64encode(data).decode("utf-8"),
        content_type,
        True
    )

def lambda_handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    path = event.get("rawPath", "/")

    if method == "OPTIONS":
        return response(204, "")

    if method == "GET" and path == "/":
        return handle_home()

    if method == "POST" and path.startswith("/upload/"):
        return handle_upload(event, path)

    if method == "GET" and path == "/random":
        return handle_random()

    return response(404, json.dumps({
        "error": "Not found",
        "method": method,
        "path": path
    }))
EOF
}

resource "local_file" "lambda_file" {
  filename = "${path.module}/lambda_function.py"
  content  = local.lambda_source
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_file.filename
  output_path = "${path.module}/lambda_function.zip"

  depends_on = [
    local_file.lambda_file
  ]
}

resource "aws_lambda_function" "cat_service" {
  function_name = "${var.project_name}-${random_id.suffix.hex}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = 30
  memory_size = 256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cat_pictures.bucket
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy.lambda_policy
  ]
}

resource "aws_apigatewayv2_api" "cat_api" {
  name          = "${var.project_name}-api-${random_id.suffix.hex}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["Content-Type"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_integration" "lambda_proxy" {
  api_id                 = aws_apigatewayv2_api.cat_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.cat_service.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.cat_api.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_proxy.id}"
}

resource "aws_apigatewayv2_route" "upload" {
  api_id    = aws_apigatewayv2_api.cat_api.id
  route_key = "POST /upload/{filename+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_proxy.id}"
}

resource "aws_apigatewayv2_route" "random" {
  api_id    = aws_apigatewayv2_api.cat_api.id
  route_key = "GET /random"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_proxy.id}"
}

resource "aws_apigatewayv2_route" "options_proxy" {
  api_id    = aws_apigatewayv2_api.cat_api.id
  route_key = "OPTIONS /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_proxy.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.cat_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway-${random_id.suffix.hex}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cat_service.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.cat_api.execution_arn}/*/*"
}

output "cat_service_url" {
  description = "Public URL of the cat picture web service."
  value       = aws_apigatewayv2_api.cat_api.api_endpoint
}

output "s3_bucket_name" {
  description = "Private S3 bucket storing uploaded cat pictures."
  value       = aws_s3_bucket.cat_pictures.bucket
}