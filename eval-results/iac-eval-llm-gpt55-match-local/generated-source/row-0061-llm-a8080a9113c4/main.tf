terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
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

variable "firehose_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream."
  type        = string
  default     = "example-firehose-elasticsearch-stream"
}

variable "elasticsearch_domain_name" {
  description = "Name of the Amazon Elasticsearch domain."
  type        = string
  default     = "example-firehose-es-domain"
}

variable "elasticsearch_index_name" {
  description = "Elasticsearch index name used by Firehose."
  type        = string
  default     = "firehose-index"
}

variable "elasticsearch_type_name" {
  description = "Elasticsearch type name used by Firehose."
  type        = string
  default     = "_doc"
}

resource "random_id" "suffix" {
  byte_length = 4
}

data "aws_caller_identity" "current" {}

resource "aws_iam_service_linked_role" "elasticsearch" {
  aws_service_name = "es.amazonaws.com"

  lifecycle {
    ignore_changes = [
      custom_suffix
    ]
  }
}

resource "aws_s3_bucket" "firehose_backup" {
  bucket = "firehose-es-backup-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_public_access_block" "firehose_backup" {
  bucket = aws_s3_bucket.firehose_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "firehose_backup" {
  bucket = aws_s3_bucket.firehose_backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "firehose_backup" {
  bucket = aws_s3_bucket.firehose_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role" "firehose_role" {
  name = "firehose-to-elasticsearch-role-${random_id.suffix.hex}"

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

resource "aws_elasticsearch_domain" "destination" {
  domain_name           = var.elasticsearch_domain_name
  elasticsearch_version = "7.10"

  cluster_config {
    instance_type  = "t3.small.elasticsearch"
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
        Resource = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.elasticsearch_domain_name}/*"
      }
    ]
  })

  depends_on = [
    aws_iam_service_linked_role.elasticsearch
  ]
}

resource "aws_iam_policy" "firehose_policy" {
  name = "firehose-to-elasticsearch-policy-${random_id.suffix.hex}"

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
        Sid    = "AllowElasticsearchAccess"
        Effect = "Allow"
        Action = [
          "es:DescribeElasticsearchDomain",
          "es:DescribeElasticsearchDomains",
          "es:DescribeElasticsearchDomainConfig",
          "es:ESHttpGet",
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpDelete",
          "es:ESHttpHead"
        ]
        Resource = [
          aws_elasticsearch_domain.destination.arn,
          "${aws_elasticsearch_domain.destination.arn}/*"
        ]
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "firehose_policy_attachment" {
  role       = aws_iam_role.firehose_role.name
  policy_arn = aws_iam_policy.firehose_policy.arn
}

resource "aws_kinesis_firehose_delivery_stream" "elasticsearch_stream" {
  name        = var.firehose_stream_name
  destination = "elasticsearch"

  elasticsearch_configuration {
    domain_arn = aws_elasticsearch_domain.destination.arn
    role_arn   = aws_iam_role.firehose_role.arn

    index_name = var.elasticsearch_index_name
    type_name  = var.elasticsearch_type_name

    index_rotation_period = "OneDay"
    buffering_interval    = 60
    buffering_size        = 5
    retry_duration        = 300

    s3_backup_mode = "FailedDocumentsOnly"

    s3_configuration {
      role_arn           = aws_iam_role.firehose_role.arn
      bucket_arn         = aws_s3_bucket.firehose_backup.arn
      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"

      prefix              = "firehose-backup/success/"
      error_output_prefix = "firehose-backup/errors/!{firehose:error-output-type}/"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.firehose_policy_attachment,
    aws_elasticsearch_domain.destination,
    aws_s3_bucket_public_access_block.firehose_backup
  ]
}

output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.elasticsearch_stream.name
}

output "elasticsearch_domain_endpoint" {
  description = "Endpoint of the Amazon Elasticsearch domain."
  value       = aws_elasticsearch_domain.destination.endpoint
}

output "backup_bucket_name" {
  description = "Name of the S3 backup bucket."
  value       = aws_s3_bucket.firehose_backup.bucket
}