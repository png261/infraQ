locals {
  name_prefix = "basic-kinesis-analytics"
}

resource "aws_kinesis_stream" "input" {
  name             = "${local.name_prefix}-input"
  shard_count      = 1
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
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
  name               = "${local.name_prefix}-role"
  assume_role_policy = data.aws_iam_policy_document.kinesis_analytics_assume_role.json
}

data "aws_iam_policy_document" "kinesis_analytics_access" {
  statement {
    sid    = "ReadInputStream"
    effect = "Allow"

    actions = [
      "kinesis:DescribeStream",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:ListShards",
    ]

    resources = [aws_kinesis_stream.input.arn]
  }

  statement {
    sid    = "WriteCloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]

    resources = ["arn:aws:logs:us-east-1:*:*"]
  }
}

resource "aws_iam_policy" "kinesis_analytics_access" {
  name        = "${local.name_prefix}-access"
  description = "Allows Kinesis Analytics to read from the benchmark input stream."
  policy      = data.aws_iam_policy_document.kinesis_analytics_access.json
}

resource "aws_iam_role_policy_attachment" "kinesis_analytics_access" {
  role       = aws_iam_role.kinesis_analytics.name
  policy_arn = aws_iam_policy.kinesis_analytics_access.arn
}

resource "aws_kinesis_analytics_application" "this" {
  name        = "${local.name_prefix}-app"
  description = "Basic Kinesis Analytics application with one Kinesis stream input."

  inputs {
    name_prefix = "SOURCE_SQL_STREAM"

    kinesis_stream {
      resource_arn = aws_kinesis_stream.input.arn
      role_arn     = aws_iam_role.kinesis_analytics.arn
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

  start_application = false

  depends_on = [aws_iam_role_policy_attachment.kinesis_analytics_access]
}
