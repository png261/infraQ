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

resource "aws_sns_topic" "s3_event_notification_topic" {
  name = "s3-event-notification-topic"
}

resource "aws_s3_bucket" "log_bucket" {
  bucket = "your-bucket-name"
}

data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    sid    = "AllowS3ToPublishObjectCreatedEvents"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = [
      "SNS:Publish"
    ]

    resources = [
      aws_sns_topic.s3_event_notification_topic.arn
    ]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        aws_s3_bucket.log_bucket.arn
      ]
    }
  }
}

resource "aws_sns_topic_policy" "s3_event_notification_topic_policy" {
  arn    = aws_sns_topic.s3_event_notification_topic.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

resource "aws_s3_bucket_notification" "log_bucket_notifications" {
  bucket = aws_s3_bucket.log_bucket.id

  topic {
    topic_arn     = aws_sns_topic.s3_event_notification_topic.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".log"
  }

  depends_on = [
    aws_sns_topic_policy.s3_event_notification_topic_policy
  ]
}