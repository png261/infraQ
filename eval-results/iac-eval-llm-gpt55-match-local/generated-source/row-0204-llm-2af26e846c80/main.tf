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
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_id" "suffix" {
  byte_length = 4
}

# MSK requires a service-linked role.
resource "aws_iam_service_linked_role" "msk" {
  aws_service_name = "kafka.amazonaws.com"
  description      = "Service-linked role for Amazon MSK"
}

resource "aws_vpc" "msk_vpc" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "msk-vpc"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.msk_vpc.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "msk-private-subnet-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.msk_vpc.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "msk-private-subnet-b"
  }
}

resource "aws_subnet" "private_c" {
  vpc_id                  = aws_vpc.msk_vpc.id
  cidr_block              = "10.20.3.0/24"
  availability_zone       = data.aws_availability_zones.available.names[2]
  map_public_ip_on_launch = false

  tags = {
    Name = "msk-private-subnet-c"
  }
}

resource "aws_security_group" "msk" {
  name        = "msk-broker-sg"
  description = "Security group for MSK brokers"
  vpc_id      = aws_vpc.msk_vpc.id

  ingress {
    description = "Allow Kafka plaintext traffic within VPC"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk_vpc.cidr_block]
  }

  ingress {
    description = "Allow Kafka TLS traffic within VPC"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk_vpc.cidr_block]
  }

  ingress {
    description = "Allow ZooKeeper TLS traffic within VPC"
    from_port   = 2182
    to_port     = 2182
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk_vpc.cidr_block]
  }

  ingress {
    description = "Allow broker-to-broker communication"
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
    Name = "msk-broker-sg"
  }
}

resource "aws_s3_bucket" "msk_logs" {
  bucket        = "msk-broker-logs-${data.aws_caller_identity.current.account_id}-${random_id.suffix.hex}"
  force_destroy = true

  tags = {
    Name = "msk-broker-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "msk_logs" {
  bucket = aws_s3_bucket.msk_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "msk_logs" {
  bucket = aws_s3_bucket.msk_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
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

resource "aws_s3_bucket_policy" "msk_logs" {
  bucket = aws_s3_bucket.msk_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.msk_logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action = "s3:PutObject"
        Resource = "${aws_s3_bucket.msk_logs.arn}/kafka-broker-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.msk_logs,
    aws_s3_bucket_ownership_controls.msk_logs
  ]
}

resource "aws_msk_cluster" "main" {
  cluster_name           = "managed-msk-cluster"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = "kafka.t3.small"
    client_subnets  = [
      aws_subnet.private_a.id,
      aws_subnet.private_b.id,
      aws_subnet.private_c.id
    ]
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = 100
      }
    }
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
      s3 {
        enabled = true
        bucket  = aws_s3_bucket.msk_logs.id
        prefix  = "kafka-broker-logs"
      }
    }
  }

  enhanced_monitoring = "DEFAULT"

  tags = {
    Name = "managed-msk-cluster"
  }

  depends_on = [
    aws_iam_service_linked_role.msk,
    aws_s3_bucket_policy.msk_logs
  ]
}

output "msk_cluster_arn" {
  value = aws_msk_cluster.main.arn
}

output "msk_cluster_name" {
  value = aws_msk_cluster.main.cluster_name
}

output "msk_bootstrap_brokers" {
  value = aws_msk_cluster.main.bootstrap_brokers
}

output "msk_bootstrap_brokers_tls" {
  value = aws_msk_cluster.main.bootstrap_brokers_tls
}

output "msk_log_bucket_name" {
  value = aws_s3_bucket.msk_logs.bucket
}