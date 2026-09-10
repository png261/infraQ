terraform {
  required_version = ">= 1.5.0"

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
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "application_name" {
  description = "Name of the Kinesis Analytics application"
  type        = string
  default     = "basic-kinesis-analytics-app"
}

variable "input_stream_name" {
  description = "Name of the input Kinesis stream"
  type        = string
  default     = "basic-kinesis-analytics-input-stream"
}

variable "output_stream_name" {
  description = "Name of the output Kinesis stream"
  type        = string
  default     = "basic-kinesis-analytics-output-stream"
}

resource "aws_kinesis_stream" "input" {
  name             = var.input_stream_name
  shard_count      = 1
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = {
    Name        = var.input_stream_name
    Environment = "demo"
  }
}

resource "aws_kinesis_stream" "output" {
  name             = var.output_stream_name
  shard_count      = 1
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = {
    Name        = var.output_stream_name
    Environment = "demo"
  }
}

resource "aws_iam_role" "kinesis_analytics_role" {
  name = "basic-kinesis-analytics-role"

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

resource "aws_iam_role_policy" "kinesis_analytics_policy" {
  name = "basic-kinesis-analytics-policy"
  role = aws_iam_role.kinesis_analytics_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards",
          "kinesis:PutRecord",
          "kinesis:PutRecords"
        ]
        Resource = [
          aws_kinesis_stream.input.arn,
          aws_kinesis_stream.output.arn
        ]
      }
    ]
  })
}

resource "aws_kinesis_analytics_application" "app" {
  name        = var.application_name
  description = "Basic Amazon Kinesis Data Analytics SQL application"

  code = <<-SQL
    CREATE OR REPLACE STREAM "DESTINATION_SQL_STREAM" (
      "ticker" VARCHAR(16),
      "price" DOUBLE
    );

    CREATE OR REPLACE PUMP "STREAM_PUMP" AS
      INSERT INTO "DESTINATION_SQL_STREAM"
      SELECT STREAM
        "ticker",
        "price"
      FROM "SOURCE_SQL_STREAM_001";
  SQL

  inputs {
    name_prefix = "SOURCE_SQL_STREAM"

    kinesis_stream {
      resource_arn = aws_kinesis_stream.input.arn
      role_arn     = aws_iam_role.kinesis_analytics_role.arn
    }

    parallelism {
      count = 1
    }

    schema {
      record_encoding = "UTF-8"

      record_columns {
        name     = "ticker"
        sql_type = "VARCHAR(16)"
        mapping  = "$.ticker"
      }

      record_columns {
        name     = "price"
        sql_type = "DOUBLE"
        mapping  = "$.price"
      }

      record_format {
        record_format_type = "JSON"

        mapping_parameters {
          json {
            record_row_path = "$"
          }
        }
      }
    }
  }

  outputs {
    name = "DESTINATION_SQL_STREAM"

    kinesis_stream {
      resource_arn = aws_kinesis_stream.output.arn
      role_arn     = aws_iam_role.kinesis_analytics_role.arn
    }

    schema {
      record_format_type = "JSON"
    }
  }

  depends_on = [
    aws_iam_role_policy.kinesis_analytics_policy
  ]

  tags = {
    Name        = var.application_name
    Environment = "demo"
  }
}

output "kinesis_analytics_application_name" {
  description = "Name of the Kinesis Analytics application"
  value       = aws_kinesis_analytics_application.app.name
}

output "input_stream_name" {
  description = "Input Kinesis stream name"
  value       = aws_kinesis_stream.input.name
}

output "output_stream_name" {
  description = "Output Kinesis stream name"
  value       = aws_kinesis_stream.output.name
}