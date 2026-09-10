data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  name_prefix = "aoss-firehose-demo"
}

resource "aws_s3_bucket" "backup" {
  bucket_prefix = "${local.name_prefix}-backup-"

  force_destroy = true
}

resource "aws_opensearchserverless_security_policy" "encryption" {
  name        = "${local.name_prefix}-enc"
  type        = "encryption"
  description = "Encryption policy for the Firehose destination collection."

  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource = [
          "collection/${local.name_prefix}"
        ]
      }
    ]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name        = "${local.name_prefix}-net"
  type        = "network"
  description = "Public network policy for the Firehose destination collection."

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource = [
            "collection/${local.name_prefix}"
          ]
        }
      ]
      AllowFromPublic = true
    }
  ])
}

resource "aws_opensearchserverless_collection" "destination" {
  name        = local.name_prefix
  type        = "TIMESERIES"
  description = "OpenSearch Serverless collection for Firehose delivery."

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network
  ]
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
  name_prefix        = "${local.name_prefix}-"
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
    sid = "OpenSearchServerlessAccess"
    actions = [
      "aoss:APIAccessAll",
      "aoss:BatchGetCollection"
    ]
    resources = [
      aws_opensearchserverless_collection.destination.arn
    ]
  }

  statement {
    sid = "CloudWatchLogsAccess"
    actions = [
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/${local.name_prefix}:log-stream:*"
    ]
  }
}

resource "aws_iam_role_policy" "firehose" {
  name   = "${local.name_prefix}-access"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose_access.json
}

resource "aws_opensearchserverless_access_policy" "firehose" {
  name        = "${local.name_prefix}-access"
  type        = "data"
  description = "Allow Firehose role to write to the destination collection."

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource = [
            "collection/${aws_opensearchserverless_collection.destination.name}"
          ]
          Permission = [
            "aoss:DescribeCollectionItems"
          ]
        },
        {
          ResourceType = "index"
          Resource = [
            "index/${aws_opensearchserverless_collection.destination.name}/*"
          ]
          Permission = [
            "aoss:CreateIndex",
            "aoss:DescribeIndex",
            "aoss:UpdateIndex",
            "aoss:WriteDocument"
          ]
        }
      ]
      Principal = [
        aws_iam_role.firehose.arn
      ]
    }
  ])
}

resource "aws_kinesis_firehose_delivery_stream" "opensearch_serverless" {
  name        = local.name_prefix
  destination = "opensearchserverless"

  opensearchserverless_configuration {
    role_arn           = aws_iam_role.firehose.arn
    collection_endpoint = aws_opensearchserverless_collection.destination.collection_endpoint
    index_name         = "firehose-index"
    s3_backup_mode     = "FailedDocumentsOnly"

    s3_configuration {
      role_arn           = aws_iam_role.firehose.arn
      bucket_arn         = aws_s3_bucket.backup.arn
      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"
    }
  }

  depends_on = [
    aws_iam_role_policy.firehose,
    aws_opensearchserverless_access_policy.firehose
  ]
}
