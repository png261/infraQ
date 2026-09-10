terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "msk-firehose-demo"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = local.name
  }
}

resource "aws_subnet" "broker_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${local.name}-broker-a"
  }
}

resource "aws_subnet" "broker_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${local.name}-broker-b"
  }
}

resource "aws_subnet" "broker_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[2]

  tags = {
    Name = "${local.name}-broker-c"
  }
}

resource "aws_security_group" "msk" {
  name        = "${local.name}-msk"
  description = "Security group for the demo MSK cluster"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-msk"
  }
}

resource "aws_s3_bucket" "firehose_logs" {
  bucket_prefix = "${local.name}-logs-"

  tags = {
    Name = "${local.name}-logs"
  }
}

resource "aws_s3_bucket_ownership_controls" "firehose_logs" {
  bucket = aws_s3_bucket.firehose_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "firehose_logs" {
  bucket = aws_s3_bucket.firehose_logs.id
  acl    = "private"

  depends_on = [aws_s3_bucket_ownership_controls.firehose_logs]
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

data "aws_iam_policy_document" "firehose_s3" {
  statement {
    effect = "Allow"

    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject",
    ]

    resources = [
      aws_s3_bucket.firehose_logs.arn,
      "${aws_s3_bucket.firehose_logs.arn}/*",
    ]
  }
}

resource "aws_iam_role" "firehose" {
  name_prefix        = "${local.name}-firehose-"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json

  inline_policy {
    name   = "s3-delivery"
    policy = data.aws_iam_policy_document.firehose_s3.json
  }
}

resource "aws_kinesis_firehose_delivery_stream" "msk_logs" {
  name        = "${local.name}-broker-logs"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.firehose_logs.arn
  }
}

resource "aws_msk_cluster" "main" {
  cluster_name           = local.name
  kafka_version          = "3.6.0"
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type = "kafka.t3.small"
    client_subnets = [
      aws_subnet.broker_a.id,
      aws_subnet.broker_b.id,
      aws_subnet.broker_c.id,
    ]
    security_groups = [aws_security_group.msk.id]
  }

  client_authentication {
    unauthenticated = true
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
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
    Name = local.name
  }
}
