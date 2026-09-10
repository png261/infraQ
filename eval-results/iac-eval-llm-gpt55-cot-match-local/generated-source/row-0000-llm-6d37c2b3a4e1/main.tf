terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_route53_zone" "primary" {
  name = "example.com"
}

resource "aws_cloudwatch_log_group" "aws_route53_example_com" {
  name              = "aws_route53_example_com"
  retention_in_days = 30
}

data "aws_iam_policy_document" "route53_query_logging_policy" {
  statement {
    sid    = "Route53LogsToCloudWatchLogs"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["route53.amazonaws.com"]
    }

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "${aws_cloudwatch_log_group.aws_route53_example_com.arn}:*"
    ]
  }
}

resource "aws_cloudwatch_log_resource_policy" "route53_query_logging_policy" {
  policy_name     = "route53-query-logging-policy"
  policy_document = data.aws_iam_policy_document.route53_query_logging_policy.json
}

resource "aws_route53_query_log" "primary" {
  depends_on = [
    aws_cloudwatch_log_resource_policy.route53_query_logging_policy
  ]

  zone_id                  = aws_route53_zone.primary.zone_id
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.aws_route53_example_com.arn
}