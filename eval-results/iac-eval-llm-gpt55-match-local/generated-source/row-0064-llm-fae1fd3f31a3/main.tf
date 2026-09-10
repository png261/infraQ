terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for created resources."
  type        = string
  default     = "firehose-aoss-demo"
}

variable "opensearch_index_name" {
  description = "OpenSearch Serverless index name used by Firehose."
  type        = string
  default     = "firehose-index"
}

resource "random_id" "suffix" {
  byte_length = 4
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_s3_bucket" "firehose_backup" {
  bucket = "${var.project_name}-backup-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_public_access_block" "firehose_backup" {
  bucket = aws_s3_bucket.firehose_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "firehose_backup" {
  bucket = aws_s3_bucket.firehose_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${var.project_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_stream" "firehose_s3_backup" {
  name           = "S3Backup"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_cloudwatch_log_stream" "firehose_aoss_delivery" {
  name           = "OpenSearchServerlessDelivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_iam_role" "firehose_role" {
  name = "${var.project_name}-firehose-role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "firehose_policy" {
  name = "${var.project_name}-firehose-policy"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3BackupAccess"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.firehose_backup.arn,
          "${aws_s3_bucket.firehose_backup.arn}/*"
        ]
      },
      {
        Sid    = "AllowCloudWatchLogging"
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.firehose.arn}:log-stream:${aws_cloudwatch_log_stream.firehose_s3_backup.name}",
          "${aws_cloudwatch_log_group.firehose.arn}:log-stream:${aws_cloudwatch_log_stream.firehose_aoss_delivery.name}"
        ]
      },
      {
        Sid    = "AllowOpenSearchServerlessAccess"
        Effect = "Allow"
        Action = [
          "aoss:APIAccessAll"
        ]
        Resource = aws_opensearchserverless_collection.firehose_collection.arn
      }
    ]
  })
}

resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "enc-${random_id.suffix.hex}"
  type = "encryption"

  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource = [
          "collection/${var.project_name}-${random_id.suffix.hex}"
        ]
      }
    ]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name = "net-${random_id.suffix.hex}"
  type = "network"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource = [
            "collection/${var.project_name}-${random_id.suffix.hex}"
          ]
        },
        {
          ResourceType = "dashboard"
          Resource = [
            "collection/${var.project_name}-${random_id.suffix.hex}"
          ]
        }
      ]
      AllowFromPublic = true
    }
  ])
}

resource "aws_opensearchserverless_collection" "firehose_collection" {
  name = "${var.project_name}-${random_id.suffix.hex}"
  type = "TIMESERIES"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network
  ]
}

resource "aws_opensearchserverless_access_policy" "firehose_access" {
  name = "access-${random_id.suffix.hex}"
  type = "data"

  policy = jsonencode([
    {
      Description = "Allow Firehose to write to OpenSearch Serverless collection"
      Principal = [
        aws_iam_role.firehose_role.arn
      ]
      Rules = [
        {
          ResourceType = "collection"
          Resource = [
            "collection/${aws_opensearchserverless_collection.firehose_collection.name}"
          ]
          Permission = [
            "aoss:DescribeCollectionItems",
            "aoss:CreateCollectionItems",
            "aoss:UpdateCollectionItems"
          ]
        },
        {
          ResourceType = "index"
          Resource = [
            "index/${aws_opensearchserverless_collection.firehose_collection.name}/*"
          ]
          Permission = [
            "aoss:CreateIndex",
            "aoss:DescribeIndex",
            "aoss:UpdateIndex",
            "aoss:WriteDocument",
            "aoss:ReadDocument"
          ]
        }
      ]
    }
  ])
}

resource "aws_kinesis_firehose_delivery_stream" "opensearch_serverless" {
  name        = "${var.project_name}-stream-${random_id.suffix.hex}"
  destination = "opensearchserverless"

  opensearchserverless_configuration {
    role_arn           = aws_iam_role.firehose_role.arn
    collection_endpoint = aws_opensearchserverless_collection.firehose_collection.collection_endpoint
    index_name         = var.opensearch_index_name

    buffering_interval = 60
    buffering_size     = 5
    retry_duration     = 300

    s3_backup_mode = "FailedDocumentsOnly"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_aoss_delivery.name
    }

    s3_configuration {
      role_arn           = aws_iam_role.firehose_role.arn
      bucket_arn         = aws_s3_bucket.firehose_backup.arn
      buffering_interval = 300
      buffering_size     = 5
      compression_format = "GZIP"

      cloudwatch_logging_options {
        enabled         = true
        log_group_name  = aws_cloudwatch_log_group.firehose.name
        log_stream_name = aws_cloudwatch_log_stream.firehose_s3_backup.name
      }
    }
  }

  depends_on = [
    aws_opensearchserverless_access_policy.firehose_access,
    aws_iam_role_policy.firehose_policy,
    aws_s3_bucket_public_access_block.firehose_backup,
    aws_s3_bucket_server_side_encryption_configuration.firehose_backup
  ]
}

output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.opensearch_serverless.name
}

output "opensearch_serverless_collection_name" {
  description = "Name of the OpenSearch Serverless collection."
  value       = aws_opensearchserverless_collection.firehose_collection.name
}

output "opensearch_serverless_collection_endpoint" {
  description = "Endpoint of the OpenSearch Serverless collection."
  value       = aws_opensearchserverless_collection.firehose_collection.collection_endpoint
}

output "s3_backup_bucket_name" {
  description = "S3 bucket used for failed document backup."
  value       = aws_s3_bucket.firehose_backup.bucket
}