terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the Lambda Layer Version will be created."
  type        = string
  default     = "us-east-1"
}

variable "lambda_layer_name" {
  description = "Name of the Lambda layer."
  type        = string
  default     = "example-lambda-layer"
}

variable "lambda_layer_zip_path" {
  description = "Path to the Lambda layer ZIP file."
  type        = string
  default     = "lambda_layer_payload.zip"
}

variable "compatible_runtimes" {
  description = "List of Lambda runtimes compatible with this layer."
  type        = list(string)
  default     = ["python3.11"]
}

variable "compatible_architectures" {
  description = "List of instruction set architectures compatible with this layer."
  type        = list(string)
  default     = ["x86_64"]
}

resource "aws_lambda_layer_version" "lambda_layer" {
  layer_name          = var.lambda_layer_name
  filename            = var.lambda_layer_zip_path
  source_code_hash    = filebase64sha256(var.lambda_layer_zip_path)
  compatible_runtimes = var.compatible_runtimes

  compatible_architectures = var.compatible_architectures

  description = "Lambda layer created from lambda_layer_payload.zip"
}

output "lambda_layer_version_arn" {
  description = "ARN of the created Lambda Layer Version."
  value       = aws_lambda_layer_version.lambda_layer.arn
}

output "lambda_layer_layer_arn" {
  description = "ARN of the Lambda Layer."
  value       = aws_lambda_layer_version.lambda_layer.layer_arn
}

output "lambda_layer_version" {
  description = "Version number of the Lambda Layer."
  value       = aws_lambda_layer_version.lambda_layer.version
}