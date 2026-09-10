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

resource "aws_s3_bucket" "firehose_backup" {
  bucket_prefix = "firehose-opensearch-backup-"
}

resource "aws_iam_role" "firehose" {
  name_prefix        = "firehose-opensearch-"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json
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

data "aws_iam_policy_document" "firehose_permissions" {
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

  statement {
    sid    = "AllowOpenSearchDelivery"
    effect = "Allow"

    actions = [
      "es:DescribeDomain",
      "es:DescribeDomains",
      "es:DescribeDomainConfig",
      "es:ESHttpGet",
      "es:ESHttpPost",
      "es:ESHttpPut"
    ]

    resources = [
      aws_opensearch_domain.firehose.arn,
      "${aws_opensearch_domain.firehose.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "firehose" {
  name   = "firehose-opensearch-delivery"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose_permissions.json
}

resource "aws_opensearch_domain" "firehose" {
  domain_name    = "firehose-opensearch-demo"
  engine_version = "OpenSearch_2.11"

  cluster_config {
    instance_type  = "t3.small.search"
    instance_count = 1
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
    volume_type = "gp3"
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.firehose.arn
        }
        Action = "es:*"
        Resource = "${aws_opensearch_domain.firehose.arn}/*"
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "opensearch" {
  name        = "firehose-opensearch-demo"
  destination = "opensearch"

  opensearch_configuration {
    domain_arn = aws_opensearch_domain.firehose.arn
    role_arn   = aws_iam_role.firehose.arn
    index_name = "firehose-index"

    s3_backup_mode = "AllDocuments"

    s3_configuration {
      role_arn           = aws_iam_role.firehose.arn
      bucket_arn         = aws_s3_bucket.firehose_backup.arn
      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"
    }
  }

  depends_on = [aws_iam_role_policy.firehose]
}
