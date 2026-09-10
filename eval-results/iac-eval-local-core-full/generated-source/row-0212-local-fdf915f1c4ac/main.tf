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

data "aws_iam_policy_document" "firehose_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "iac-eval-msk-vpc"
  }
}

resource "aws_subnet" "broker_a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "iac-eval-msk-broker-a"
  }
}

resource "aws_subnet" "broker_b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "iac-eval-msk-broker-b"
  }
}

resource "aws_subnet" "broker_c" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[2]

  tags = {
    Name = "iac-eval-msk-broker-c"
  }
}

resource "aws_security_group" "msk" {
  name        = "iac-eval-msk-sg"
  description = "Security group for the benchmark MSK cluster"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Kafka plaintext within the VPC"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iac-eval-msk-sg"
  }
}

resource "aws_kms_key" "msk" {
  description             = "KMS key for MSK encryption at rest"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/iac-eval"
  retention_in_days = 7
}

resource "aws_s3_bucket" "logs" {
  bucket_prefix = "iac-eval-msk-logs-"
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_acl" "logs" {
  depends_on = [aws_s3_bucket_ownership_controls.logs]

  bucket = aws_s3_bucket.logs.id
  acl    = "private"
}

resource "aws_iam_role" "firehose" {
  name_prefix        = "iac-eval-firehose-"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json

  inline_policy {
    name = "firehose-s3-delivery"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetBucketLocation",
            "s3:ListBucket",
            "s3:ListBucketMultipartUploads"
          ]
          Resource = aws_s3_bucket.logs.arn
        },
        {
          Effect = "Allow"
          Action = [
            "s3:AbortMultipartUpload",
            "s3:GetObject",
            "s3:PutObject"
          ]
          Resource = "${aws_s3_bucket.logs.arn}/*"
        }
      ]
    })
  }
}

resource "aws_kinesis_firehose_delivery_stream" "msk_logs" {
  name        = "iac-eval-msk-logs"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.logs.arn
  }
}

resource "aws_msk_cluster" "this" {
  cluster_name           = "iac-eval-msk"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = "kafka.t3.small"
    client_subnets  = [aws_subnet.broker_a.id, aws_subnet.broker_b.id, aws_subnet.broker_c.id]
    security_groups = [aws_security_group.msk.id]
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.msk.arn
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }

      s3 {
        enabled = true
        bucket  = aws_s3_bucket.logs.id
        prefix  = "msk/"
      }

      firehose {
        enabled         = true
        delivery_stream = aws_kinesis_firehose_delivery_stream.msk_logs.name
      }
    }
  }

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
}
