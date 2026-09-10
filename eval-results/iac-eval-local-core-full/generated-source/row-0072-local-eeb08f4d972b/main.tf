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
  name               = "basic-sql-kinesis-analytics-role"
  assume_role_policy = data.aws_iam_policy_document.kinesis_analytics_assume_role.json
}

resource "aws_kinesisanalyticsv2_application" "sql" {
  name                   = "basic-sql-kinesis-analytics-app"
  runtime_environment    = "SQL-1_0"
  service_execution_role = aws_iam_role.kinesis_analytics.arn
}
