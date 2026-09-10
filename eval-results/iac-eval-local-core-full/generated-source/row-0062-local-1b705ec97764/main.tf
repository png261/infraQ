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

locals {
  name = "iac-eval-firehose-opensearch"
}

resource "aws_s3_bucket" "backup" {
  bucket_prefix = "iac-eval-firehose-backup-"

  tags = {
    Name = "${local.name}-backup"
  }
}

resource "aws_opensearch_domain" "destination" {
  domain_name    = local.name
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

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  tags = {
    Name = local.name
  }
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
  name_prefix        = "iac-eval-firehose-"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json
}

data "aws_iam_policy_document" "firehose_access" {
  statement {
    sid = "S3BackupAccess"

    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject"
    ]

    resources = [
      aws_s3_bucket.backup.arn,
      "${aws_s3_bucket.backup.arn}/*"
    ]
  }

  statement {
    sid = "OpenSearchDeliveryAccess"

    actions = [
      "es:DescribeDomain",
      "es:DescribeDomains",
      "es:DescribeDomainConfig",
      "es:ESHttpDelete",
      "es:ESHttpGet",
      "es:ESHttpHead",
      "es:ESHttpPost",
      "es:ESHttpPut"
    ]

    resources = [
      aws_opensearch_domain.destination.arn,
      "${aws_opensearch_domain.destination.arn}/*"
    ]
  }

  statement {
    sid = "FirehoseLoggingAccess"

    actions = [
      "logs:PutLogEvents"
    ]

    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/${local.name}:log-stream:*"
    ]
  }
}

resource "aws_iam_role_policy" "firehose" {
  name   = "${local.name}-access"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose_access.json
}

resource "aws_kinesis_firehose_delivery_stream" "opensearch" {
  name        = local.name
  destination = "opensearch"

  opensearch_configuration {
    domain_arn = aws_opensearch_domain.destination.arn
    role_arn   = aws_iam_role.firehose.arn
    index_name = "firehose-index"

    s3_configuration {
      role_arn           = aws_iam_role.firehose.arn
      bucket_arn         = aws_s3_bucket.backup.arn
      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"
    }
  }

  depends_on = [
    aws_iam_role_policy.firehose
  ]
}
