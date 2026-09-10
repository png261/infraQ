terraform {
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

resource "aws_s3_bucket" "logs" {
  bucket_prefix = "iac-eval-log-bucket-"
}

resource "aws_sns_topic" "log_notifications" {
  name_prefix = "iac-eval-log-notifications-"
}

resource "aws_s3_bucket_notification" "log_object_created" {
  bucket = aws_s3_bucket.logs.id

  topic {
    topic_arn     = aws_sns_topic.log_notifications.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".log"
  }
}
