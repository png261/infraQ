provider "aws" {
  region = "us-east-1"
}

resource "aws_lambda_layer_version" "benchmark" {
  filename   = "lambda_layer_payload.zip"
  layer_name = "benchmark-lambda-layer"
}
