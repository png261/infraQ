data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  name_prefix   = "iac-eval-firehose-es"
  es_domain_arn = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${local.name_prefix}"
}

resource "aws_s3_bucket" "firehose_backup" {
  bucket = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_elasticsearch_domain" "destination" {
  domain_name           = local.name_prefix
  elasticsearch_version = "7.10"

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowFirehoseDeliveryRole"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.firehose.arn
        }
        Action = [
          "es:DescribeElasticsearchDomain",
          "es:DescribeElasticsearchDomains",
          "es:DescribeElasticsearchDomainConfig",
          "es:ESHttpPost",
          "es:ESHttpPut"
        ]
        Resource = [
          local.es_domain_arn,
          "${local.es_domain_arn}/*"
        ]
      }
    ]
  })

  cluster_config {
    instance_type  = "t3.small.elasticsearch"
    instance_count = 1
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
    volume_type = "gp2"
  }
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

resource "aws_iam_role" "firehose" {
  name               = "${local.name_prefix}-role"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json
}

data "aws_iam_policy_document" "firehose_delivery" {
  statement {
    sid    = "AllowS3BackupDelivery"
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
    sid    = "AllowElasticsearchDelivery"
    effect = "Allow"

    actions = [
      "es:DescribeElasticsearchDomain",
      "es:DescribeElasticsearchDomains",
      "es:DescribeElasticsearchDomainConfig",
      "es:ESHttpPost",
      "es:ESHttpPut"
    ]

    resources = [
      aws_elasticsearch_domain.destination.arn,
      "${aws_elasticsearch_domain.destination.arn}/*"
    ]
  }

  statement {
    sid    = "AllowFirehoseLogging"
    effect = "Allow"

    actions = [
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "firehose_delivery" {
  name   = "${local.name_prefix}-delivery-policy"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose_delivery.json
}

resource "aws_kinesis_firehose_delivery_stream" "elasticsearch" {
  name        = "${local.name_prefix}-stream"
  destination = "elasticsearch"

  elasticsearch_configuration {
    domain_arn = aws_elasticsearch_domain.destination.arn
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

  depends_on = [aws_iam_role_policy.firehose_delivery]
}
