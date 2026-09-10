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
  default     = "firehose-es-vpc"
}

variable "elasticsearch_version" {
  description = "Amazon Elasticsearch version."
  type        = string
  default     = "7.10"
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_iam_service_linked_role" "elasticsearch" {
  aws_service_name = "es.amazonaws.com"

  lifecycle {
    ignore_changes = [
      custom_suffix
    ]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

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
  cidr_block              = "10.50.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.50.2.0/24"
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

resource "aws_security_group" "firehose" {
  name        = "${var.project_name}-firehose-sg"
  description = "Security group for Kinesis Firehose ENIs"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow outbound HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.50.0.0/16"]
  }

  tags = {
    Name = "${var.project_name}-firehose-sg"
  }
}

resource "aws_security_group" "elasticsearch" {
  name        = "${var.project_name}-es-sg"
  description = "Security group for Amazon Elasticsearch domain"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow HTTPS from Firehose"
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
    Name = "${var.project_name}-es-sg"
  }
}

resource "aws_s3_bucket" "backup" {
  bucket        = "${var.project_name}-backup-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  force_destroy = true

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

resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${var.project_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_stream" "firehose" {
  name           = "elasticsearch-delivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_elasticsearch_domain" "main" {
  domain_name           = "${var.project_name}-domain"
  elasticsearch_version = var.elasticsearch_version

  cluster_config {
    instance_type  = "t3.small.elasticsearch"
    instance_count = 1
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 10
  }

  vpc_options {
    subnet_ids         = [aws_subnet.public_a.id]
    security_group_ids = [aws_security_group.elasticsearch.id]
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
    Name = "${var.project_name}-domain"
  }

  depends_on = [
    aws_iam_service_linked_role.elasticsearch
  ]
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
  name               = "${var.project_name}-firehose-role"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json
}

data "aws_iam_policy_document" "firehose_policy" {
  statement {
    sid    = "AllowS3BackupAccess"
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
      aws_s3_bucket.backup.arn,
      "${aws_s3_bucket.backup.arn}/*"
    ]
  }

  statement {
    sid    = "AllowElasticsearchAccess"
    effect = "Allow"

    actions = [
      "es:DescribeElasticsearchDomain",
      "es:DescribeElasticsearchDomains",
      "es:DescribeElasticsearchDomainConfig",
      "es:ESHttpDelete",
      "es:ESHttpGet",
      "es:ESHttpHead",
      "es:ESHttpPost",
      "es:ESHttpPut"
    ]

    resources = [
      aws_elasticsearch_domain.main.arn,
      "${aws_elasticsearch_domain.main.arn}/*"
    ]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:PutLogEvents"
    ]

    resources = [
      "${aws_cloudwatch_log_group.firehose.arn}:log-stream:${aws_cloudwatch_log_stream.firehose.name}"
    ]
  }

  statement {
    sid    = "AllowVpcNetworking"
    effect = "Allow"

    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:CreateNetworkInterfacePermission",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "firehose" {
  name   = "${var.project_name}-firehose-policy"
  policy = data.aws_iam_policy_document.firehose_policy.json
}

resource "aws_iam_role_policy_attachment" "firehose" {
  role       = aws_iam_role.firehose.name
  policy_arn = aws_iam_policy.firehose.arn
}

data "aws_iam_policy_document" "elasticsearch_access_policy" {
  statement {
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        aws_iam_role.firehose.arn
      ]
    }

    actions = [
      "es:ESHttpDelete",
      "es:ESHttpGet",
      "es:ESHttpHead",
      "es:ESHttpPost",
      "es:ESHttpPut"
    ]

    resources = [
      "${aws_elasticsearch_domain.main.arn}/*"
    ]
  }
}

resource "aws_elasticsearch_domain_policy" "main" {
  domain_name     = aws_elasticsearch_domain.main.domain_name
  access_policies = data.aws_iam_policy_document.elasticsearch_access_policy.json
}

resource "aws_kinesis_firehose_delivery_stream" "main" {
  name        = "${var.project_name}-stream"
  destination = "elasticsearch"

  elasticsearch_configuration {
    domain_arn = aws_elasticsearch_domain.main.arn
    role_arn   = aws_iam_role.firehose.arn

    index_name = "firehose-index"
    type_name  = "_doc"

    buffering_interval = 60
    buffering_size     = 5

    retry_duration = 300

    s3_backup_mode = "AllDocuments"

    s3_configuration {
      role_arn           = aws_iam_role.firehose.arn
      bucket_arn         = aws_s3_bucket.backup.arn
      buffering_interval = 300
      buffering_size     = 5
      compression_format = "GZIP"
    }

    vpc_config {
      subnet_ids         = [aws_subnet.public_a.id, aws_subnet.public_b.id]
      security_group_ids = [aws_security_group.firehose.id]
      role_arn           = aws_iam_role.firehose.arn
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.firehose,
    aws_elasticsearch_domain_policy.main
  ]

  tags = {
    Name = "${var.project_name}-stream"
  }
}

output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.main.name
}

output "elasticsearch_domain_endpoint" {
  description = "Endpoint of the Elasticsearch domain."
  value       = aws_elasticsearch_domain.main.endpoint
}

output "backup_bucket_name" {
  description = "S3 bucket used for Firehose backup documents."
  value       = aws_s3_bucket.backup.bucket
}