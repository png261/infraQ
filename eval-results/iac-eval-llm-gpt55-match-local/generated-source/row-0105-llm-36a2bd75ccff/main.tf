terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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
  description = "AWS region where the S3 bucket will be created."
  type        = string
  default     = "us-east-1"
}

variable "object_key" {
  description = "The key name for the S3 object."
  type        = string
  default     = "example/my_object.txt"
}

variable "object_content" {
  description = "The content to store in the S3 object."
  type        = string
  default     = "This is the content stored in my_object inside the S3 bucket."
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "my_bucket" {
  bucket        = "my-bucket-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Name        = "my_bucket"
    Environment = "cleanup-demo"
  }
}

resource "aws_s3_bucket_metric" "my_bucket_metric" {
  bucket = aws_s3_bucket.my_bucket.id
  name   = "my_bucket_metric"
}

resource "aws_s3_object" "my_object" {
  bucket       = aws_s3_bucket.my_bucket.id
  key          = var.object_key
  content      = var.object_content
  content_type = "text/plain"

  depends_on = [
    aws_s3_bucket.my_bucket
  ]
}

output "bucket_name" {
  description = "The name of the created S3 bucket."
  value       = aws_s3_bucket.my_bucket.bucket
}

output "bucket_metric_name" {
  description = "The name of the S3 bucket metric."
  value       = aws_s3_bucket_metric.my_bucket_metric.name
}

output "object_key" {
  description = "The key of the uploaded S3 object."
  value       = aws_s3_object.my_object.key
}