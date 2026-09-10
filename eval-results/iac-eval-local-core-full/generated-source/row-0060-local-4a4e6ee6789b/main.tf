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
    sid = "S3StagingAccess"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject"
    ]
    resources = [
      aws_s3_bucket.firehose_staging.arn,
      "${aws_s3_bucket.firehose_staging.arn}/*"
    ]
  }

  statement {
    sid = "RedshiftAccess"
    actions = [
      "redshift:DescribeClusters",
      "redshift:GetClusterCredentials"
    ]
    resources = ["*"]
  }
}

resource "aws_s3_bucket" "firehose_staging" {
  bucket_prefix = "firehose-redshift-staging-"
}

resource "aws_iam_role" "firehose_delivery" {
  name_prefix        = "firehose-redshift-delivery-"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json

  inline_policy {
    name   = "firehose-redshift-access"
    policy = data.aws_iam_policy_document.firehose_access.json
  }
}

resource "aws_redshift_cluster" "destination" {
  cluster_identifier  = "firehose-redshift-destination"
  database_name       = "analytics"
  master_username     = "adminuser"
  master_password     = var.redshift_master_password
  node_type           = "dc2.large"
  cluster_type        = "single-node"
  publicly_accessible = true
  skip_final_snapshot = true
}

resource "aws_kinesis_firehose_delivery_stream" "redshift" {
  name        = "firehose-redshift-delivery-stream"
  destination = "redshift"

  redshift_configuration {
    role_arn           = aws_iam_role.firehose_delivery.arn
    cluster_jdbcurl    = "jdbc:redshift://${aws_redshift_cluster.destination.endpoint}/${aws_redshift_cluster.destination.database_name}"
    username           = aws_redshift_cluster.destination.master_username
    password           = var.redshift_master_password
    data_table_name    = "public.events"
    data_table_columns = "event_id,event_type,event_timestamp,payload"
    copy_options       = "json 'auto'"
    s3_backup_mode     = "Enabled"

    s3_configuration {
      role_arn           = aws_iam_role.firehose_delivery.arn
      bucket_arn         = aws_s3_bucket.firehose_staging.arn
      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"
    }
  }
}
