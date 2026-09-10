resource "aws_s3_bucket" "firehose_backup" {
  bucket        = var.bucket_name
  bucket_prefix = var.bucket_name == null ? var.bucket_prefix : null
  force_destroy = var.force_destroy_backup_bucket
}

data "aws_iam_policy_document" "firehose_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  name_prefix        = "firehose-http-endpoint-"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json
}

data "aws_iam_policy_document" "firehose_s3_backup" {
  statement {
    sid = "AllowS3BackupAccess"

    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject",
    ]

    resources = [
      aws_s3_bucket.firehose_backup.arn,
      "${aws_s3_bucket.firehose_backup.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "firehose_s3_backup" {
  name   = "firehose-s3-backup-access"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose_s3_backup.json
}

resource "aws_kinesis_firehose_delivery_stream" "http_endpoint" {
  name        = var.firehose_stream_name
  destination = "http_endpoint"

  http_endpoint_configuration {
    name               = var.http_endpoint_name
    url                = var.http_endpoint_url
    access_key         = var.http_endpoint_access_key
    role_arn           = aws_iam_role.firehose.arn
    s3_backup_mode     = "FailedDataOnly"
    buffering_size     = 5
    buffering_interval = 300
    retry_duration     = 60

    s3_configuration {
      role_arn           = aws_iam_role.firehose.arn
      bucket_arn         = aws_s3_bucket.firehose_backup.arn
      prefix             = var.s3_backup_prefix
      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"
    }

    request_configuration {
      content_encoding = "GZIP"
    }
  }

  depends_on = [aws_iam_role_policy.firehose_s3_backup]
}
