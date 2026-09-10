data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.name_prefix}-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${var.name_prefix}-private-b"
  }
}

resource "aws_subnet" "private_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[2]

  tags = {
    Name = "${var.name_prefix}-private-c"
  }
}

resource "aws_security_group" "msk" {
  name        = "${var.name_prefix}-sg"
  description = "Security group for the MSK cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Kafka TLS access from inside the VPC"
    from_port   = 9094
    to_port     = 9094
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
    Name = "${var.name_prefix}-sg"
  }
}

resource "aws_s3_bucket" "msk_logs" {
  bucket_prefix = "${var.name_prefix}-logs-"
  force_destroy = true

  tags = {
    Name = "${var.name_prefix}-logs"
  }
}

resource "aws_s3_bucket_ownership_controls" "msk_logs" {
  bucket = aws_s3_bucket.msk_logs.id

  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_acl" "msk_logs" {
  depends_on = [aws_s3_bucket_ownership_controls.msk_logs]

  bucket = aws_s3_bucket.msk_logs.id
  acl    = "private"
}

resource "aws_s3_bucket_policy" "msk_logs" {
  bucket = aws_s3_bucket.msk_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMSKLogDeliveryBucketChecks"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.msk_logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.name_prefix}-cluster/*"
          }
        }
      },
      {
        Sid    = "AllowMSKLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.msk_logs.arn}/broker-logs/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
            "s3:x-amz-acl"      = "bucket-owner-full-control"
          }
          ArnLike = {
            "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.name_prefix}-cluster/*"
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.name_prefix}"
  retention_in_days = 7
}

resource "aws_msk_cluster" "main" {
  cluster_name           = "${var.name_prefix}-cluster"
  kafka_version          = var.kafka_version
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = [aws_subnet.private_a.id, aws_subnet.private_b.id, aws_subnet.private_c.id]
    security_groups = [aws_security_group.msk.id]
  }

  logging_info {
    broker_logs {
      s3 {
        enabled = true
        bucket  = aws_s3_bucket.msk_logs.id
        prefix  = "broker-logs/"
      }
    }
  }

  tags = {
    Name = "${var.name_prefix}-cluster"
  }
}
