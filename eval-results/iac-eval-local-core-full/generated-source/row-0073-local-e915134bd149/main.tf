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

data "aws_iam_policy_document" "kinesis_analytics_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["kinesisanalytics.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "kinesis_analytics_logs" {
  statement {
    sid    = "WriteApplicationLogs"
    effect = "Allow"

    actions = [
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]

    resources = [
      aws_cloudwatch_log_group.kinesis_analytics.arn,
      "${aws_cloudwatch_log_group.kinesis_analytics.arn}:log-stream:${aws_cloudwatch_log_stream.kinesis_analytics.name}",
    ]
  }
}

resource "aws_cloudwatch_log_group" "kinesis_analytics" {
  name              = "/aws/kinesis-analytics/basic-application"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_stream" "kinesis_analytics" {
  name           = "basic-application-log-stream"
  log_group_name = aws_cloudwatch_log_group.kinesis_analytics.name
}

resource "aws_iam_role" "kinesis_analytics" {
  name               = "basic-kinesis-analytics-role"
  assume_role_policy = data.aws_iam_policy_document.kinesis_analytics_assume_role.json

  inline_policy {
    name   = "cloudwatch-logs-write"
    policy = data.aws_iam_policy_document.kinesis_analytics_logs.json
  }
}

resource "aws_s3_bucket" "kinesis_analytics" {
  bucket_prefix = "basic-kinesis-analytics-"
}

resource "aws_kinesis_analytics_application" "basic" {
  name        = "basic-kinesis-analytics-application"
  description = "Basic Kinesis Analytics application with CloudWatch logging."

  cloudwatch_logging_options {
    log_stream_arn = aws_cloudwatch_log_stream.kinesis_analytics.arn
    role_arn       = aws_iam_role.kinesis_analytics.arn
  }
}
