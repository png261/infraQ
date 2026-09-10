terraform {
  required_version = ">= 1.0.0"

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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "application_name" {
  description = "Name of the Kinesis Analytics application."
  type        = string
  default     = "basic-kinesis-analytics-app"
}

variable "log_group_name" {
  description = "Name of the CloudWatch Log Group."
  type        = string
  default     = "/aws/kinesis-analytics/basic-app"
}

variable "log_stream_name" {
  description = "Name of the CloudWatch Log Stream."
  type        = string
  default     = "application-log-stream"
}

resource "aws_cloudwatch_log_group" "kinesis_analytics" {
  name              = var.log_group_name
  retention_in_days = 7
}

resource "aws_cloudwatch_log_stream" "kinesis_analytics" {
  name           = var.log_stream_name
  log_group_name = aws_cloudwatch_log_group.kinesis_analytics.name
}

resource "aws_iam_role" "kinesis_analytics" {
  name = "${var.application_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "kinesisanalytics.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "kinesis_analytics_logs" {
  name = "${var.application_name}-cloudwatch-logs-policy"
  role = aws_iam_role.kinesis_analytics.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_stream.kinesis_analytics.arn
        ]
      }
    ]
  })
}

resource "aws_kinesis_analytics_application" "basic" {
  name        = var.application_name
  description = "Basic Amazon Kinesis Analytics SQL application with CloudWatch logging enabled."

  code = <<SQL
CREATE OR REPLACE STREAM "DESTINATION_SQL_STREAM" (
  example_column VARCHAR(64)
);
SQL

  cloudwatch_logging_options {
    log_stream_arn = aws_cloudwatch_log_stream.kinesis_analytics.arn
    role_arn       = aws_iam_role.kinesis_analytics.arn
  }

  start_application = false

  depends_on = [
    aws_iam_role_policy.kinesis_analytics_logs
  ]
}

output "kinesis_analytics_application_name" {
  description = "Name of the Kinesis Analytics application."
  value       = aws_kinesis_analytics_application.basic.name
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group."
  value       = aws_cloudwatch_log_group.kinesis_analytics.name
}

output "cloudwatch_log_stream_name" {
  description = "Name of the CloudWatch Log Stream."
  value       = aws_cloudwatch_log_stream.kinesis_analytics.name
}