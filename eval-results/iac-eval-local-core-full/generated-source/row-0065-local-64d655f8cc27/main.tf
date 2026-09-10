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
    sid = "ElasticsearchAccess"
    actions = [
      "es:DescribeElasticsearchDomain",
      "es:DescribeElasticsearchDomains",
      "es:DescribeElasticsearchDomainConfig",
      "es:ESHttpGet",
      "es:ESHttpPost",
      "es:ESHttpPut"
    ]
    resources = [
      aws_elasticsearch_domain.firehose_destination.arn,
      "${aws_elasticsearch_domain.firehose_destination.arn}/*"
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
    sid = "CloudWatchLogsAccess"
    actions = [
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "iac-eval-firehose-es-vpc"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "iac-eval-firehose-es-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "iac-eval-firehose-es-private-b"
  }
}

resource "aws_security_group" "elasticsearch" {
  name        = "iac-eval-firehose-es-sg"
  description = "Allow Firehose VPC delivery to Elasticsearch"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from within VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iac-eval-firehose-es-sg"
  }
}

resource "aws_s3_bucket" "firehose_backup" {
  bucket_prefix = "iac-eval-firehose-es-backup-"

  force_destroy = true

  tags = {
    Name = "iac-eval-firehose-es-backup"
  }
}

resource "aws_iam_role" "firehose" {
  name               = "iac-eval-firehose-es-role"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json
}

resource "aws_iam_role_policy" "firehose" {
  name   = "iac-eval-firehose-es-policy"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose_access.json
}

resource "aws_elasticsearch_domain" "firehose_destination" {
  domain_name           = "iac-eval-firehose-es"
  elasticsearch_version = "7.10"

  cluster_config {
    instance_type           = "t3.small.elasticsearch"
    instance_count          = 2
    zone_awareness_enabled  = true

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
    security_group_ids = [aws_security_group.elasticsearch.id]
  }

  tags = {
    Name = "iac-eval-firehose-es"
  }
}

resource "aws_kinesis_firehose_delivery_stream" "elasticsearch" {
  name        = "iac-eval-firehose-es-stream"
  destination = "elasticsearch"

  elasticsearch_configuration {
    domain_arn = aws_elasticsearch_domain.firehose_destination.arn
    role_arn   = aws_iam_role.firehose.arn
    index_name = "firehose-index"
    type_name  = "_doc"

    s3_configuration {
      bucket_arn = aws_s3_bucket.firehose_backup.arn
      role_arn   = aws_iam_role.firehose.arn
    }

    vpc_config {
      role_arn           = aws_iam_role.firehose.arn
      subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
      security_group_ids = [aws_security_group.elasticsearch.id]
    }
  }

  depends_on = [aws_iam_role_policy.firehose]
}
