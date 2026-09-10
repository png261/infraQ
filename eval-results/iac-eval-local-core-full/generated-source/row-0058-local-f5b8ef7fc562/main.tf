terraform {
  required_version = ">= 1.6.0"

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

resource "aws_iam_role" "kinesis_analytics" {
  name               = "basic-flink-analytics-role"
  assume_role_policy = data.aws_iam_policy_document.kinesis_analytics_assume_role.json
}

resource "aws_kinesisanalyticsv2_application" "flink" {
  name                   = "basic-flink-application"
  runtime_environment    = "FLINK-1_19"
  service_execution_role = aws_iam_role.kinesis_analytics.arn

  application_configuration {
    flink_application_configuration {
      checkpoint_configuration {
        configuration_type = "DEFAULT"
      }

      monitoring_configuration {
        configuration_type = "DEFAULT"
      }

      parallelism_configuration {
        configuration_type = "DEFAULT"
      }
    }
  }
}
