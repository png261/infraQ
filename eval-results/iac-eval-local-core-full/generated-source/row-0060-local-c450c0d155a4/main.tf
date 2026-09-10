data "aws_caller_identity" "current" {}

data "aws_ip_ranges" "firehose" {
  regions  = ["us-east-1"]
  services = ["KINESIS_FIREHOSE"]
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

data "aws_iam_policy_document" "firehose_access" {
  statement {
    sid = "AllowS3BucketAccess"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads"
    ]
    resources = [
      aws_s3_bucket.firehose_backup.arn
    ]
  }

  statement {
    sid = "AllowS3ObjectAccess"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject"
    ]
    resources = [
      "${aws_s3_bucket.firehose_backup.arn}/*"
    ]
  }

  statement {
    sid = "AllowRedshiftCopyCredentials"
    actions = [
      "redshift:DescribeClusters"
    ]
    resources = ["*"]
  }
}

resource "aws_s3_bucket" "firehose_backup" {
  bucket_prefix = "firehose-redshift-backup-"

  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "firehose_backup" {
  bucket                  = aws_s3_bucket.firehose_backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "firehose" {
  name_prefix        = "firehose-redshift-"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json
}

resource "aws_iam_role_policy" "firehose_access" {
  name   = "firehose-redshift-access"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose_access.json
}

resource "aws_security_group" "redshift_firehose" {
  name_prefix = "redshift-firehose-"
  description = "Allow Firehose service ranges to connect to Redshift on port 5439."

  ingress {
    description = "Amazon Kinesis Data Firehose to Redshift"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = data.aws_ip_ranges.firehose.cidr_blocks
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_redshift_cluster" "destination" {
  cluster_identifier     = "firehose-redshift-destination"
  database_name          = var.redshift_database_name
  master_username        = var.redshift_master_username
  master_password        = var.redshift_master_password
  node_type              = "dc2.large"
  cluster_type           = "single-node"
  publicly_accessible    = true
  vpc_security_group_ids = [aws_security_group.redshift_firehose.id]
  skip_final_snapshot    = true
}

resource "aws_kinesis_firehose_delivery_stream" "redshift" {
  name        = "firehose-redshift-delivery-stream"
  destination = "redshift"

  redshift_configuration {
    role_arn        = aws_iam_role.firehose.arn
    cluster_jdbcurl = "jdbc:redshift://${aws_redshift_cluster.destination.endpoint}/${var.redshift_database_name}"
    username        = var.redshift_master_username
    password        = var.redshift_master_password
    data_table_name = var.redshift_table_name
    copy_options    = "json 'auto'"
    s3_backup_mode  = "Enabled"

    s3_backup_configuration {
      role_arn           = aws_iam_role.firehose.arn
      bucket_arn         = aws_s3_bucket.firehose_backup.arn
      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"
    }

    s3_configuration {
      role_arn           = aws_iam_role.firehose.arn
      bucket_arn         = aws_s3_bucket.firehose_backup.arn
      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"
    }
  }

  depends_on = [aws_iam_role_policy.firehose_access]
}
