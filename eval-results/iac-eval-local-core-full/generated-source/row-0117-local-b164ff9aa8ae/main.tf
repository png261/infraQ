terraform {
  required_version = ">= 1.6.0"

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

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  sns_topic_name = "s3-event-notification-topic"
  sns_topic_arn  = "arn:${data.aws_partition.current.partition}:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${local.sns_topic_name}"
}

data "aws_iam_policy_document" "s3_publish_to_sns" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["SNS:Publish"]

    resources = [local.sns_topic_arn]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.your_bucket.arn]
    }
  }
}

resource "aws_sns_topic" "s3_event_notification_topic" {
  name   = local.sns_topic_name
  policy = data.aws_iam_policy_document.s3_publish_to_sns.json
}

resource "aws_s3_bucket" "your_bucket" {
  bucket = "your-bucket-name"
}

resource "aws_s3_bucket_notification" "your_bucket_notifications" {
  bucket = aws_s3_bucket.your_bucket.id

  topic {
    topic_arn     = aws_sns_topic.s3_event_notification_topic.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".log"
  }
}
