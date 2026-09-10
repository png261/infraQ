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

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "source" {
  bucket = "mybucket"
}

resource "aws_s3_bucket" "analytics_destination" {
  bucket = "${aws_s3_bucket.source.bucket}-analytics-results"
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "analytics_destination" {
  bucket = aws_s3_bucket.analytics_destination.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "analytics_destination" {
  statement {
    sid    = "AllowS3AnalyticsExport"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.analytics_destination.arn}/analytics/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.source.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "analytics_destination" {
  bucket = aws_s3_bucket.analytics_destination.id
  policy = data.aws_iam_policy_document.analytics_destination.json
}

resource "aws_s3_bucket_analytics_configuration" "entire_bucket" {
  bucket = aws_s3_bucket.source.id
  name   = "entire-bucket-analytics"

  storage_class_analysis {
    data_export {
      output_schema_version = "V_1"

      destination {
        s3_bucket_destination {
          bucket_arn = aws_s3_bucket.analytics_destination.arn
          format     = "CSV"
          prefix     = "analytics/"
        }
      }
    }
  }

  depends_on = [
    aws_s3_bucket_policy.analytics_destination
  ]
}