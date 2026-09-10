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
  type        = string
  description = "AWS region to deploy resources into."
  default     = "us-east-1"
}

variable "redshift_database_name" {
  type        = string
  description = "Name of the initial Redshift database."
  default     = "analyticsdb"
}

variable "redshift_master_username" {
  type        = string
  description = "Master username for the Redshift cluster."
  default     = "adminuser"
}

variable "redshift_master_password" {
  type        = string
  description = "Master password for the Redshift cluster."
  sensitive   = true
  default     = "ChangeMe12345!"
}

variable "redshift_table_name" {
  type        = string
  description = "Destination Redshift table name. The table must exist before records can be loaded successfully."
  default     = "firehose_events"
}

variable "redshift_node_type" {
  type        = string
  description = "Redshift node type."
  default     = "dc2.large"
}

variable "firehose_stream_name" {
  type        = string
  description = "Name of the Kinesis Firehose Delivery Stream."
  default     = "redshift-firehose-delivery-stream"
}

resource "random_id" "suffix" {
  byte_length = 4
}

data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------
# Networking
# -----------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "firehose-redshift-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "firehose-redshift-igw"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "firehose-redshift-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.40.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "firehose-redshift-public-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "firehose-redshift-public-rt"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# -----------------------------
# Redshift
# -----------------------------

resource "aws_security_group" "redshift" {
  name        = "firehose-redshift-sg-${random_id.suffix.hex}"
  description = "Allow Redshift access for Firehose delivery"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow Redshift PostgreSQL access"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"

    # For production, restrict this to known Firehose service CIDRs or private connectivity.
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "firehose-redshift-sg"
  }
}

resource "aws_redshift_subnet_group" "main" {
  name       = "firehose-redshift-subnet-group-${random_id.suffix.hex}"
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = {
    Name = "firehose-redshift-subnet-group"
  }
}

resource "aws_redshift_cluster" "main" {
  cluster_identifier        = "firehose-redshift-${random_id.suffix.hex}"
  database_name             = var.redshift_database_name
  master_username           = var.redshift_master_username
  master_password           = var.redshift_master_password
  node_type                 = var.redshift_node_type
  cluster_type              = "single-node"
  publicly_accessible       = true
  skip_final_snapshot       = true
  encrypted                 = true
  cluster_subnet_group_name = aws_redshift_subnet_group.main.name
  vpc_security_group_ids    = [aws_security_group.redshift.id]

  tags = {
    Name = "firehose-redshift-cluster"
  }
}

# -----------------------------
# S3 bucket for Firehose staging and backup
# -----------------------------

resource "aws_s3_bucket" "firehose" {
  bucket        = "firehose-redshift-${random_id.suffix.hex}"
  force_destroy = true

  tags = {
    Name = "firehose-redshift-staging-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "firehose" {
  bucket = aws_s3_bucket.firehose.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "firehose" {
  bucket = aws_s3_bucket.firehose.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -----------------------------
# CloudWatch Logs
# -----------------------------

resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${var.firehose_stream_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_stream" "redshift_delivery" {
  name           = "RedshiftDelivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_cloudwatch_log_stream" "s3_backup" {
  name           = "S3Backup"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

# -----------------------------
# IAM for Firehose
# -----------------------------

resource "aws_iam_role" "firehose" {
  name = "firehose-redshift-role-${random_id.suffix.hex}"

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
    Name = "firehose-redshift-role"
  }
}

resource "aws_iam_policy" "firehose" {
  name        = "firehose-redshift-policy-${random_id.suffix.hex}"
  description = "Permissions for Kinesis Firehose to deliver data to Redshift using S3 staging."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Access"
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
          aws_s3_bucket.firehose.arn,
          "${aws_s3_bucket.firehose.arn}/*"
        ]
      },
      {
        Sid    = "RedshiftAccess"
        Effect = "Allow"
        Action = [
          "redshift:DescribeClusters",
          "redshift:GetClusterCredentials"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.firehose.arn}:log-stream:${aws_cloudwatch_log_stream.redshift_delivery.name}",
          "${aws_cloudwatch_log_group.firehose.arn}:log-stream:${aws_cloudwatch_log_stream.s3_backup.name}"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "firehose" {
  role       = aws_iam_role.firehose.name
  policy_arn = aws_iam_policy.firehose.arn
}

# -----------------------------
# Kinesis Firehose Delivery Stream
# -----------------------------

resource "aws_kinesis_firehose_delivery_stream" "redshift" {
  name        = var.firehose_stream_name
  destination = "redshift"

  redshift_configuration {
    role_arn        = aws_iam_role.firehose.arn
    cluster_jdbcurl = "jdbc:redshift://${aws_redshift_cluster.main.endpoint}/${var.redshift_database_name}"
    username        = var.redshift_master_username
    password        = var.redshift_master_password

    data_table_name = var.redshift_table_name
    copy_options    = "JSON 'auto' TIMEFORMAT 'auto'"

    retry_duration = 3600

    s3_backup_mode = "Enabled"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.redshift_delivery.name
    }

    s3_configuration {
      role_arn           = aws_iam_role.firehose.arn
      bucket_arn         = aws_s3_bucket.firehose.arn
      prefix             = "redshift-staging/!{timestamp:yyyy/MM/dd/HH}/"
      error_output_prefix = "redshift-staging-errors/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd/HH}/"

      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"

      cloudwatch_logging_options {
        enabled         = true
        log_group_name  = aws_cloudwatch_log_group.firehose.name
        log_stream_name = aws_cloudwatch_log_stream.redshift_delivery.name
      }
    }

    s3_backup_configuration {
      role_arn           = aws_iam_role.firehose.arn
      bucket_arn         = aws_s3_bucket.firehose.arn
      prefix             = "redshift-backup/!{timestamp:yyyy/MM/dd/HH}/"
      error_output_prefix = "redshift-backup-errors/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd/HH}/"

      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"

      cloudwatch_logging_options {
        enabled         = true
        log_group_name  = aws_cloudwatch_log_group.firehose.name
        log_stream_name = aws_cloudwatch_log_stream.s3_backup.name
      }
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.firehose,
    aws_redshift_cluster.main
  ]

  tags = {
    Name = "firehose-redshift-delivery-stream"
  }
}

# -----------------------------
# Outputs
# -----------------------------

output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Firehose Delivery Stream."
  value       = aws_kinesis_firehose_delivery_stream.redshift.name
}

output "redshift_cluster_identifier" {
  description = "Redshift cluster identifier."
  value       = aws_redshift_cluster.main.cluster_identifier
}

output "redshift_endpoint" {
  description = "Redshift cluster endpoint."
  value       = aws_redshift_cluster.main.endpoint
}

output "redshift_database_name" {
  description = "Redshift database name."
  value       = var.redshift_database_name
}

output "redshift_destination_table" {
  description = "Redshift destination table name expected by Firehose."
  value       = var.redshift_table_name
}

output "s3_staging_bucket" {
  description = "S3 bucket used by Firehose for staging and backup."
  value       = aws_s3_bucket.firehose.bucket
}