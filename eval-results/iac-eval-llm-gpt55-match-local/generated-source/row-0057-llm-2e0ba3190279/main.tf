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
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "kinesis_stream_name" {
  description = "Name of the input Kinesis data stream."
  type        = string
  default     = "basic-kinesis-analytics-input-stream"
}

variable "analytics_application_name" {
  description = "Name of the Kinesis Analytics application."
  type        = string
  default     = "basic-kinesis-analytics-application"
}

resource "aws_kinesis_stream" "input_stream" {
  name             = var.kinesis_stream_name
  shard_count      = 1
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = {
    Name        = var.kinesis_stream_name
    Environment = "example"
  }
}

resource "aws_iam_role" "kinesis_analytics_role" {
  name = "basic-kinesis-analytics-service-role"

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
  name = "basic-kinesis-analytics-read-stream-policy"
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
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.input_stream.arn
      }
    ]
  })
}

resource "aws_kinesis_analytics_application" "analytics_application" {
  name        = var.analytics_application_name
  description = "Basic Amazon Kinesis Analytics SQL application with a Kinesis stream input."

  inputs {
    name_prefix = "SOURCE_SQL_STREAM"

    kinesis_stream {
      resource_arn = aws_kinesis_stream.input_stream.arn
      role_arn     = aws_iam_role.kinesis_analytics_role.arn
    }

    schema {
      record_encoding = "UTF-8"

      record_columns {
        name     = "event_id"
        sql_type = "VARCHAR(64)"
        mapping  = "$.event_id"
      }

      record_columns {
        name     = "event_type"
        sql_type = "VARCHAR(64)"
        mapping  = "$.event_type"
      }

      record_columns {
        name     = "event_value"
        sql_type = "DOUBLE"
        mapping  = "$.event_value"
      }

      record_columns {
        name     = "event_time"
        sql_type = "VARCHAR(64)"
        mapping  = "$.event_time"
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

  application_code = <<-SQL
    CREATE OR REPLACE STREAM "DESTINATION_SQL_STREAM" (
      event_id VARCHAR(64),
      event_type VARCHAR(64),
      event_value DOUBLE,
      event_time VARCHAR(64)
    );

    CREATE OR REPLACE PUMP "STREAM_PUMP" AS
      INSERT INTO "DESTINATION_SQL_STREAM"
      SELECT STREAM
        event_id,
        event_type,
        event_value,
        event_time
      FROM "SOURCE_SQL_STREAM_001";
  SQL

  tags = {
    Name        = var.analytics_application_name
    Environment = "example"
  }
}

output "kinesis_stream_name" {
  description = "Name of the created Kinesis input stream."
  value       = aws_kinesis_stream.input_stream.name
}

output "kinesis_stream_arn" {
  description = "ARN of the created Kinesis input stream."
  value       = aws_kinesis_stream.input_stream.arn
}

output "kinesis_analytics_application_name" {
  description = "Name of the Kinesis Analytics application."
  value       = aws_kinesis_analytics_application.analytics_application.name
}

output "kinesis_analytics_application_arn" {
  description = "ARN of the Kinesis Analytics application."
  value       = aws_kinesis_analytics_application.analytics_application.arn
}