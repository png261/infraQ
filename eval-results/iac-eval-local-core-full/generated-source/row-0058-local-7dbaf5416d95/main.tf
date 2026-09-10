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
  name               = "basic-flink-analytics-application-role"
  assume_role_policy = data.aws_iam_policy_document.kinesis_analytics_assume_role.json
}

resource "aws_kinesisanalyticsv2_application" "flink" {
  name                   = "basic-flink-analytics-application"
  runtime_environment    = "FLINK-1_18"
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
