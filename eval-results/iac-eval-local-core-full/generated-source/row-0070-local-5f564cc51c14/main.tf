terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "firehose_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "firehose_s3_access" {
  statement {
    sid    = "AllowS3BucketAccess"
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
    ]

    resources = [aws_s3_bucket.firehose_destination.arn]
  }

  statement {
    sid    = "AllowS3ObjectDelivery"
    effect = "Allow"

    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = ["${aws_s3_bucket.firehose_destination.arn}/*"]
  }
}

resource "aws_s3_bucket" "firehose_destination" {
  bucket        = "firehose-extended-s3-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  force_destroy = true
}

resource "aws_iam_role" "firehose_delivery" {
  name               = "firehose-extended-s3-delivery-role"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json

  inline_policy {
    name   = "firehose-s3-access"
    policy = data.aws_iam_policy_document.firehose_s3_access.json
  }
}

resource "aws_kinesis_firehose_delivery_stream" "extended_s3" {
  name        = "extended-s3-firehose-stream"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_delivery.arn
    bucket_arn = aws_s3_bucket.firehose_destination.arn
  }
}
