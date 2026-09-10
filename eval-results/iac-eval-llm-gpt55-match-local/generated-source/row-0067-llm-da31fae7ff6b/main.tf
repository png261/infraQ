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
  type        = string
  description = "AWS region to deploy resources into."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Project name used for resource naming."
  default     = "firehose-opensearch-vpc"
}

variable "opensearch_domain_name" {
  type        = string
  description = "Name of the OpenSearch domain."
  default     = "firehose-os-domain"
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route" "public_internet" {
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

resource "aws_security_group" "opensearch" {
  name        = "${var.project_name}-opensearch-sg"
  description = "Security group for OpenSearch domain"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow HTTPS from Firehose security group"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.firehose.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-opensearch-sg"
  }
}

resource "aws_security_group" "firehose" {
  name        = "${var.project_name}-firehose-sg"
  description = "Security group used by Kinesis Firehose ENIs"
  vpc_id      = aws_vpc.main.id

  egress {
    description     = "Allow HTTPS to OpenSearch"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.opensearch.id]
  }

  egress {
    description = "Allow HTTPS to AWS service endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-firehose-sg"
  }
}

resource "aws_s3_bucket" "backup" {
  bucket = "${var.project_name}-backup-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-backup"
  }
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

resource "aws_iam_role" "firehose" {
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

resource "aws_iam_role_policy" "firehose" {
  name = "${var.project_name}-firehose-policy"
  role = aws_iam_role.firehose.id

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
        Sid    = "AllowOpenSearchAccess"
        Effect = "Allow"
        Action = [
          "es:DescribeElasticsearchDomain",
          "es:DescribeElasticsearchDomains",
          "es:DescribeElasticsearchDomainConfig",
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpGet"
        ]
        Resource = [
          aws_opensearch_domain.main.arn,
          "${aws_opensearch_domain.main.arn}/*"
        ]
      },
      {
        Sid    = "AllowVpcEniManagement"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:CreateNetworkInterfacePermission",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
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

resource "aws_opensearch_domain" "main" {
  domain_name    = var.opensearch_domain_name
  engine_version = "OpenSearch_2.11"

  cluster_config {
    instance_type          = "t3.small.search"
    instance_count         = 2
    zone_awareness_enabled = true

    zone_awareness_config {
      availability_zone_count = 2
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 10
  }

  vpc_options {
    subnet_ids = [
      aws_subnet.public_a.id,
      aws_subnet.public_b.id
    ]

    security_group_ids = [
      aws_security_group.opensearch.id
    ]
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
          AWS = aws_iam_role.firehose.arn
        }
        Action = [
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpGet"
        ]
        Resource = "${aws_opensearch_domain.main.arn}/*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-opensearch"
  }

  depends_on = [
    aws_iam_role.firehose
  ]
}

resource "aws_kinesis_firehose_delivery_stream" "opensearch" {
  name        = "${var.project_name}-stream"
  destination = "opensearch"

  opensearch_configuration {
    role_arn   = aws_iam_role.firehose.arn
    domain_arn = aws_opensearch_domain.main.arn

    index_name = "firehose-index"
    type_name  = "_doc"

    s3_backup_mode = "AllDocuments"

    buffering_interval = 60
    buffering_size     = 5

    retry_duration = 300

    s3_configuration {
      role_arn           = aws_iam_role.firehose.arn
      bucket_arn         = aws_s3_bucket.backup.arn
      buffering_interval = 60
      buffering_size     = 5
      compression_format = "GZIP"
    }

    vpc_config {
      subnet_ids = [
        aws_subnet.public_a.id,
        aws_subnet.public_b.id
      ]

      security_group_ids = [
        aws_security_group.firehose.id
      ]

      role_arn = aws_iam_role.firehose.arn
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_opensearch.name
    }
  }

  tags = {
    Name = "${var.project_name}-firehose-stream"
  }

  depends_on = [
    aws_opensearch_domain.main,
    aws_iam_role_policy.firehose,
    aws_s3_bucket_public_access_block.backup,
    aws_s3_bucket_server_side_encryption_configuration.backup
  ]
}

output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.opensearch.name
}

output "opensearch_domain_endpoint" {
  description = "OpenSearch domain endpoint."
  value       = aws_opensearch_domain.main.endpoint
}

output "backup_bucket_name" {
  description = "S3 bucket used for Firehose backup."
  value       = aws_s3_bucket.backup.bucket
}