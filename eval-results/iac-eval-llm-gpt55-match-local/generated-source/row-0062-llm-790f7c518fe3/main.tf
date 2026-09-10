terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for created resources."
  type        = string
  default     = "firehose-opensearch-demo"
}

variable "opensearch_instance_type" {
  description = "OpenSearch data node instance type."
  type        = string
  default     = "t3.small.search"
}

variable "opensearch_engine_version" {
  description = "OpenSearch engine version."
  type        = string
  default     = "OpenSearch_2.11"
}

variable "firehose_index_name" {
  description = "OpenSearch index name used by Firehose."
  type        = string
  default     = "firehose-index"
}

resource "random_id" "suffix" {
  byte_length = 4
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_s3_bucket" "backup" {
  bucket        = "${var.project_name}-backup-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

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

resource "aws_cloudwatch_log_stream" "firehose_opensearch" {
  name           = "OpenSearchDelivery"
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

resource "aws_opensearch_domain" "this" {
  domain_name    = "${var.project_name}-${random_id.suffix.hex}"
  engine_version = var.opensearch_engine_version

  cluster_config {
    instance_type  = var.opensearch_instance_type
    instance_count = 1
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 10
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

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.firehose_role.arn
        }
        Action = [
          "es:ESHttpGet",
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpDelete",
          "es:ESHttpHead"
        ]
        Resource = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.project_name}-${random_id.suffix.hex}/*"
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
          aws_s3_bucket.backup.arn,
          "${aws_s3_bucket.backup.arn}/*"
        ]
      },
      {
        Sid    = "AllowOpenSearchDelivery"
        Effect = "Allow"
        Action = [
          "es:DescribeDomain",
          "es:DescribeDomains",
          "es:DescribeDomainConfig",
          "es:ESHttpGet",
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpDelete",
          "es:ESHttpHead"
        ]
        Resource = [
          aws_opensearch_domain.this.arn,
          "${aws_opensearch_domain.this.arn}/*"
        ]
      },
      {
        Sid    = "AllowFirehoseLogging"
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.firehose.arn}:log-stream:${aws_cloudwatch_log_stream.firehose_opensearch.name}"
        ]
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "opensearch_stream" {
  name        = "${var.project_name}-stream-${random_id.suffix.hex}"
  destination = "opensearch"

  opensearch_configuration {
    domain_arn = aws_opensearch_domain.this.arn
    role_arn   = aws_iam_role.firehose_role.arn

    index_name = var.firehose_index_name
    type_name  = "_doc"

    index_rotation_period = "OneDay"

    buffering_interval = 60
    buffering_size     = 5

    retry_duration = 300

    s3_backup_mode = "FailedDocumentsOnly"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_opensearch.name
    }

    s3_configuration {
      role_arn           = aws_iam_role.firehose_role.arn
      bucket_arn         = aws_s3_bucket.backup.arn
      prefix             = "firehose-backup/success/"
      error_output_prefix = "firehose-backup/errors/!{firehose:error-output-type}/"

      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"

      cloudwatch_logging_options {
        enabled         = true
        log_group_name  = aws_cloudwatch_log_group.firehose.name
        log_stream_name = aws_cloudwatch_log_stream.firehose_opensearch.name
      }
    }
  }

  depends_on = [
    aws_iam_role_policy.firehose_policy,
    aws_opensearch_domain.this,
    aws_s3_bucket_public_access_block.backup,
    aws_s3_bucket_server_side_encryption_configuration.backup
  ]
}

output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.opensearch_stream.name
}

output "opensearch_domain_name" {
  description = "Name of the OpenSearch domain."
  value       = aws_opensearch_domain.this.domain_name
}

output "opensearch_endpoint" {
  description = "Endpoint of the OpenSearch domain."
  value       = aws_opensearch_domain.this.endpoint
}

output "backup_bucket_name" {
  description = "Name of the S3 backup bucket."
  value       = aws_s3_bucket.backup.bucket
}