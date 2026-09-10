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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name."
  type        = string
  default     = "log-notification-bucket"
}

variable "sns_topic_name" {
  description = "Name of the SNS topic."
  type        = string
  default     = "s3-log-object-created-topic"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "logs" {
  bucket = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_sns_topic" "log_notifications" {
  name = var.sns_topic_name
}

resource "aws_s3_bucket_notification" "log_object_created" {
  bucket = aws_s3_bucket.logs.id

  topic {
    topic_arn     = aws_sns_topic.log_notifications.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".log"
  }
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket."
  value       = aws_s3_bucket.logs.bucket
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic receiving S3 object-created notifications."
  value       = aws_sns_topic.log_notifications.arn
}