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
  region = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "msk-firehose-demo"
}

variable "kafka_version" {
  description = "Kafka version for the MSK cluster."
  type        = string
  default     = "3.6.0"
}

variable "broker_instance_type" {
  description = "MSK broker instance type."
  type        = string
  default     = "kafka.t3.small"
}

variable "broker_volume_size" {
  description = "EBS storage size per broker in GiB."
  type        = number
  default     = 100
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_vpc" "main" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.40.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-b"
  }
}

resource "aws_subnet" "private_c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.40.3.0/24"
  availability_zone       = data.aws_availability_zones.available.names[2]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-c"
  }
}

resource "aws_security_group" "msk" {
  name        = "${var.project_name}-msk-sg"
  description = "Security group for MSK brokers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow Kafka plaintext traffic within the VPC"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    description = "Allow Kafka TLS traffic within the VPC"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    description = "Allow ZooKeeper traffic within the VPC"
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    description = "Allow ZooKeeper TLS traffic within the VPC"
    from_port   = 2182
    to_port     = 2182
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    description = "Allow broker-to-broker traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
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

resource "aws_s3_bucket" "msk_logs" {
  bucket = "${var.project_name}-msk-logs-${random_id.suffix.hex}"

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

  tags = {
    Name = "${var.project_name}-firehose-role"
  }
}

resource "aws_iam_policy" "firehose_policy" {
  name        = "${var.project_name}-firehose-policy-${random_id.suffix.hex}"
  description = "Allows Kinesis Firehose to deliver MSK logs to S3."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3BucketAccess"
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
      },
      {
        Sid    = "AllowCloudWatchLogging"
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

resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${var.project_name}"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-firehose-log-group"
  }
}

resource "aws_cloudwatch_log_stream" "firehose_s3_delivery" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_kinesis_firehose_delivery_stream" "msk_logs" {
  name        = "${var.project_name}-msk-logs-${random_id.suffix.hex}"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose_role.arn
    bucket_arn          = aws_s3_bucket.msk_logs.arn
    prefix              = "msk-broker-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "msk-broker-logs-errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"

    buffering_size     = 5
    buffering_interval = 300
    compression_format = "GZIP"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_s3_delivery.name
    }
  }

  tags = {
    Name = "${var.project_name}-msk-logs-firehose"
  }

  depends_on = [
    aws_iam_role_policy_attachment.firehose_policy_attachment,
    aws_s3_bucket_public_access_block.msk_logs,
    aws_s3_bucket_server_side_encryption_configuration.msk_logs
  ]
}

resource "aws_msk_cluster" "main" {
  cluster_name           = "${var.project_name}-cluster"
  kafka_version          = var.kafka_version
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = [
      aws_subnet.private_a.id,
      aws_subnet.private_b.id,
      aws_subnet.private_c.id
    ]
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.broker_volume_size
      }
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
  }

  client_authentication {
    unauthenticated = true
  }

  logging_info {
    broker_logs {
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
    aws_kinesis_firehose_delivery_stream.msk_logs
  ]
}

output "msk_cluster_arn" {
  description = "ARN of the MSK cluster."
  value       = aws_msk_cluster.main.arn
}

output "msk_bootstrap_brokers" {
  description = "Plaintext bootstrap broker connection string."
  value       = aws_msk_cluster.main.bootstrap_brokers
}

output "msk_bootstrap_brokers_tls" {
  description = "TLS bootstrap broker connection string."
  value       = aws_msk_cluster.main.bootstrap_brokers_tls
}

output "firehose_delivery_stream_name" {
  description = "Kinesis Firehose delivery stream receiving MSK logs."
  value       = aws_kinesis_firehose_delivery_stream.msk_logs.name
}

output "s3_log_bucket_name" {
  description = "S3 bucket where Firehose stores MSK broker logs."
  value       = aws_s3_bucket.msk_logs.bucket
}