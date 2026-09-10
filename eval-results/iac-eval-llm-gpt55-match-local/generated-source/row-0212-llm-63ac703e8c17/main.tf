terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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
  description = "Name prefix for all resources."
  type        = string
  default     = "terraform-msk-logging"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

resource "aws_vpc" "main" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "msk" {
  count = 3

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-subnet-${count.index + 1}"
  }
}

resource "aws_security_group" "msk" {
  name        = "${var.project_name}-msk-sg"
  description = "Security group for MSK cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow Kafka and related traffic from within the VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-msk-sg"
  }
}

resource "aws_kms_key" "msk" {
  description             = "KMS key for MSK encryption at rest"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-msk-kms-key"
  }
}

resource "aws_kms_alias" "msk" {
  name          = "alias/${var.project_name}-msk"
  target_key_id = aws_kms_key.msk.key_id
}

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.project_name}"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-msk-log-group"
  }
}

resource "aws_s3_bucket" "msk_logs" {
  bucket = "${var.project_name}-msk-logs-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  tags = {
    Name = "${var.project_name}-msk-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "msk_logs" {
  bucket = aws_s3_bucket.msk_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "msk_logs" {
  bucket = aws_s3_bucket.msk_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "msk_logs" {
  bucket = aws_s3_bucket.msk_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "firehose_role" {
  name = "${var.project_name}-firehose-role"

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

  tags = {
    Name = "${var.project_name}-firehose-role"
  }
}

resource "aws_iam_role_policy" "firehose_policy" {
  name = "${var.project_name}-firehose-policy"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
          aws_s3_bucket.msk_logs.arn,
          "${aws_s3_bucket.msk_logs.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "msk_logs" {
  name        = "${var.project_name}-msk-firehose"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose_role.arn
    bucket_arn         = aws_s3_bucket.msk_logs.arn
    prefix             = "firehose-msk-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "firehose-msk-errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"

    buffering_size     = 5
    buffering_interval = 300
    compression_format = "GZIP"
  }

  tags = {
    Name = "${var.project_name}-msk-firehose"
  }

  depends_on = [
    aws_iam_role_policy.firehose_policy
  ]
}

resource "aws_msk_configuration" "main" {
  name           = "${var.project_name}-msk-config"
  kafka_versions = ["3.6.0"]

  server_properties = <<PROPERTIES
auto.create.topics.enable=true
delete.topic.enable=true
log.retention.hours=168
num.partitions=3
default.replication.factor=3
min.insync.replicas=2
PROPERTIES
}

resource "aws_msk_cluster" "main" {
  cluster_name           = "${var.project_name}-cluster"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = "kafka.t3.small"
    client_subnets  = aws_subnet.msk[*].id
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = 100
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.main.arn
    revision = aws_msk_configuration.main.latest_revision
  }

  client_authentication {
    unauthenticated = true
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.msk.arn

    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
  }

  enhanced_monitoring = "PER_TOPIC_PER_BROKER"

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }

      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }

      s3 {
        enabled = true
        bucket  = aws_s3_bucket.msk_logs.id
        prefix  = "msk-broker-logs/"
      }

      firehose {
        enabled         = true
        delivery_stream = aws_kinesis_firehose_delivery_stream.msk_logs.name
      }
    }
  }

  tags = {
    Name = "${var.project_name}-cluster"
  }

  depends_on = [
    aws_cloudwatch_log_group.msk,
    aws_s3_bucket_public_access_block.msk_logs,
    aws_s3_bucket_server_side_encryption_configuration.msk_logs,
    aws_kinesis_firehose_delivery_stream.msk_logs
  ]
}

output "msk_cluster_arn" {
  description = "ARN of the MSK cluster."
  value       = aws_msk_cluster.main.arn
}

output "msk_cluster_name" {
  description = "Name of the MSK cluster."
  value       = aws_msk_cluster.main.cluster_name
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group receiving MSK broker logs."
  value       = aws_cloudwatch_log_group.msk.name
}

output "s3_log_bucket_name" {
  description = "S3 bucket receiving MSK broker logs."
  value       = aws_s3_bucket.msk_logs.id
}

output "firehose_delivery_stream_name" {
  description = "Kinesis Firehose delivery stream receiving MSK broker logs."
  value       = aws_kinesis_firehose_delivery_stream.msk_logs.name
}

output "kms_key_arn" {
  description = "KMS key ARN used for MSK encryption at rest."
  value       = aws_kms_key.msk.arn
}