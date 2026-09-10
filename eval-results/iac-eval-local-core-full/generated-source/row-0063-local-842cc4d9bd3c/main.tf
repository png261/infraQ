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
    sid    = "AllowS3BackupAccess"
    effect = "Allow"

    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject"
    ]

    resources = [
      aws_s3_bucket.firehose_backup.arn,
      "${aws_s3_bucket.firehose_backup.arn}/*"
    ]
  }
}

resource "aws_s3_bucket" "firehose_backup" {
  bucket = var.backup_bucket_name

  tags = {
    Name        = var.backup_bucket_name
    Environment = "dev"
  }
}

resource "aws_iam_role" "firehose_delivery" {
  name               = var.firehose_role_name
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json

  inline_policy {
    name   = "firehose-s3-backup-access"
    policy = data.aws_iam_policy_document.firehose_s3_access.json
  }

  tags = {
    Name        = var.firehose_role_name
    Environment = "dev"
  }
}

resource "aws_kinesis_firehose_delivery_stream" "splunk" {
  name        = var.delivery_stream_name
  destination = "splunk"

  splunk_configuration {
    hec_endpoint               = var.splunk_hec_endpoint
    hec_endpoint_type          = var.splunk_hec_endpoint_type
    hec_token                  = var.splunk_hec_token
    s3_backup_mode             = "FailedEventsOnly"
    retry_duration             = 300
    buffering_size             = 5
    buffering_interval         = 60
    cloudwatch_logging_options {
      enabled = false
    }

    s3_configuration {
      role_arn           = aws_iam_role.firehose_delivery.arn
      bucket_arn         = aws_s3_bucket.firehose_backup.arn
      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"
    }
  }

  tags = {
    Name        = var.delivery_stream_name
    Environment = "dev"
  }
}
