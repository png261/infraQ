data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "firehose_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "firehose_access" {
  statement {
    sid = "S3BackupAccess"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject"
    ]
    resources = [
      aws_s3_bucket.firehose_backup.arn,
      "${aws_s3_bucket.firehose_backup.arn}/*"
    ]
  }

  statement {
    sid = "OpenSearchAccess"
    actions = [
      "es:DescribeDomain",
      "es:DescribeDomains",
      "es:DescribeDomainConfig",
      "es:ESHttpPost",
      "es:ESHttpPut"
    ]
    resources = [
      aws_opensearch_domain.firehose_destination.arn,
      "${aws_opensearch_domain.firehose_destination.arn}/*"
    ]
  }

  statement {
    sid = "VpcNetworkInterfaceAccess"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:CreateNetworkInterfacePermission",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "CloudWatchLoggingAccess"
    actions   = ["logs:PutLogEvents"]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/example-opensearch-vpc:log-stream:*"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "firehose-opensearch-vpc"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "firehose-opensearch-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "firehose-opensearch-private-b"
  }
}

resource "aws_security_group" "opensearch" {
  name        = "firehose-opensearch-sg"
  description = "Allow HTTPS access from Firehose VPC ENIs to OpenSearch"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from inside the VPC"
    from_port   = 443
    to_port     = 443
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
    Name = "firehose-opensearch-sg"
  }
}

resource "aws_s3_bucket" "firehose_backup" {
  bucket_prefix = "firehose-opensearch-backup-"

  force_destroy = true

  tags = {
    Name = "firehose-opensearch-backup"
  }
}

resource "aws_iam_role" "firehose" {
  name               = "firehose-opensearch-vpc-role"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json
}

resource "aws_iam_role_policy" "firehose" {
  name   = "firehose-opensearch-vpc-policy"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose_access.json
}

resource "aws_opensearch_domain" "firehose_destination" {
  domain_name    = "firehose-vpc-domain"
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
    volume_size = 10
    volume_type = "gp3"
  }

  vpc_options {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.opensearch.id]
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  tags = {
    Name = "firehose-vpc-domain"
  }
}

resource "aws_kinesis_firehose_delivery_stream" "opensearch" {
  name        = "example-opensearch-vpc-stream"
  destination = "opensearch"

  opensearch_configuration {
    domain_arn = aws_opensearch_domain.firehose_destination.arn
    role_arn   = aws_iam_role.firehose.arn
    index_name = "firehose-index"

    s3_configuration {
      role_arn   = aws_iam_role.firehose.arn
      bucket_arn = aws_s3_bucket.firehose_backup.arn
    }

    vpc_config {
      subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
      security_group_ids = [aws_security_group.opensearch.id]
      role_arn           = aws_iam_role.firehose.arn
    }
  }

  depends_on = [aws_iam_role_policy.firehose]
}
