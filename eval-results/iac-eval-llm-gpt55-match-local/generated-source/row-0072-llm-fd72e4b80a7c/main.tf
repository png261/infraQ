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
  region = "us-east-1"
}

variable "application_name" {
  description = "Name of the Amazon Kinesis Data Analytics V2 SQL application."
  type        = string
  default     = "basic-kinesis-sql-analytics-app"
}

variable "input_stream_name" {
  description = "Name of the input Kinesis Data Stream."
  type        = string
  default     = "basic-kda-sql-input-stream"
}

variable "output_stream_name" {
  description = "Name of the output Kinesis Data Stream."
  type        = string
  default     = "basic-kda-sql-output-stream"
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
  name = "${var.application_name}-execution-role"

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

resource "aws_iam_policy" "kinesis_analytics_policy" {
  name        = "${var.application_name}-stream-access-policy"
  description = "Allows Kinesis Data Analytics to read from the input stream and write to the output stream."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadInputKinesisStream"
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListShards",
          "kinesis:ListStreams"
        ]
        Resource = aws_kinesis_stream.input.arn
      },
      {
        Sid    = "WriteOutputKinesisStream"
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:PutRecord",
          "kinesis:PutRecords",
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.output.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "kinesis_analytics_policy_attachment" {
  role       = aws_iam_role.kinesis_analytics_role.name
  policy_arn = aws_iam_policy.kinesis_analytics_policy.arn
}

resource "aws_kinesisanalyticsv2_application" "sql_application" {
  name                   = var.application_name
  runtime_environment    = "SQL-1_0"
  service_execution_role = aws_iam_role.kinesis_analytics_role.arn

  application_configuration {
    application_code_configuration {
      code_content_type = "PLAINTEXT"

      code_content {
        text_content = <<-SQL
          CREATE OR REPLACE STREAM "DESTINATION_SQL_STREAM" (
            ticker_symbol VARCHAR(16),
            sector VARCHAR(32),
            price DOUBLE,
            event_time TIMESTAMP
          );

          CREATE OR REPLACE PUMP "STREAM_PUMP" AS
            INSERT INTO "DESTINATION_SQL_STREAM"
            SELECT STREAM
              ticker_symbol,
              sector,
              price,
              ROWTIME AS event_time
            FROM "SOURCE_SQL_STREAM_001";
        SQL
      }
    }

    sql_application_configuration {
      input {
        name_prefix = "SOURCE_SQL_STREAM"

        kinesis_streams_input {
          resource_arn = aws_kinesis_stream.input.arn
        }

        input_parallelism {
          count = 1
        }

        input_schema {
          record_encoding = "UTF-8"

          record_column {
            name     = "ticker_symbol"
            mapping  = "$.ticker_symbol"
            sql_type = "VARCHAR(16)"
          }

          record_column {
            name     = "sector"
            mapping  = "$.sector"
            sql_type = "VARCHAR(32)"
          }

          record_column {
            name     = "price"
            mapping  = "$.price"
            sql_type = "DOUBLE"
          }

          record_format {
            record_format_type = "JSON"

            mapping_parameters {
              json_mapping_parameters {
                record_row_path = "$"
              }
            }
          }
        }
      }

      output {
        name = "DESTINATION_SQL_STREAM"

        kinesis_streams_output {
          resource_arn = aws_kinesis_stream.output.arn
        }

        destination_schema {
          record_format_type = "JSON"
        }
      }
    }
  }

  tags = {
    Name        = var.application_name
    Environment = "demo"
  }

  depends_on = [
    aws_iam_role_policy_attachment.kinesis_analytics_policy_attachment
  ]
}

output "kinesis_analytics_application_name" {
  description = "Name of the Kinesis Data Analytics SQL application."
  value       = aws_kinesisanalyticsv2_application.sql_application.name
}

output "input_stream_name" {
  description = "Name of the input Kinesis Data Stream."
  value       = aws_kinesis_stream.input.name
}

output "output_stream_name" {
  description = "Name of the output Kinesis Data Stream."
  value       = aws_kinesis_stream.output.name
}