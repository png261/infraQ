data "aws_caller_identity" "current" {}

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
      "s3:ListBucketMultipartUploads"
    ]

    resources = [aws_s3_bucket.firehose_destination.arn]
  }

  statement {
    sid    = "AllowS3ObjectAccess"
    effect = "Allow"

    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetObject",
      "s3:PutObject"
    ]

    resources = ["${aws_s3_bucket.firehose_destination.arn}/*"]
  }
}

resource "aws_s3_bucket" "firehose_destination" {
  bucket = "firehose-dynamic-partitioning-${data.aws_caller_identity.current.account_id}"
}

resource "aws_iam_role" "firehose_role" {
  name               = "firehose-dynamic-partitioning-role"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json

  inline_policy {
    name   = "firehose-s3-access"
    policy = data.aws_iam_policy_document.firehose_s3_access.json
  }
}

resource "aws_kinesis_firehose_delivery_stream" "extended_s3_dynamic_partitioning" {
  name        = "extended-s3-dynamic-partitioning-stream"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.firehose_destination.arn

    buffering_interval = 60
    buffering_size     = 64
    compression_format = "GZIP"
    prefix             = "!{partitionKeyFromQuery:partition_key}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/"

    dynamic_partitioning_configuration {
      enabled = true
    }

    processing_configuration {
      enabled = true

      processors {
        type = "MetadataExtraction"

        parameters {
          parameter_name  = "MetadataExtractionQuery"
          parameter_value = "{partition_key:.partition_key}"
        }

        parameters {
          parameter_name  = "JsonParsingEngine"
          parameter_value = "JQ-1.6"
        }
      }
    }
  }
}
