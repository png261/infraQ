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

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "sqlserver_audit_bucket" {
  bucket = "sqlserver-audit-option-group-pike-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "sqlserver-audit-option-group-pike"
    Environment = "example"
  }
}

resource "aws_s3_bucket_public_access_block" "sqlserver_audit_bucket" {
  bucket = aws_s3_bucket.sqlserver_audit_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sqlserver_audit_bucket" {
  bucket = aws_s3_bucket.sqlserver_audit_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role" "rds_sqlserver_audit_role" {
  name = "rds-sqlserver-audit-option-group-pike-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "rds-sqlserver-audit-option-group-pike-role"
  }
}

resource "aws_iam_policy" "rds_sqlserver_audit_s3_policy" {
  name        = "rds-sqlserver-audit-option-group-pike-s3-policy"
  description = "Allows RDS SQL Server Audit to write audit files to the configured S3 bucket."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.sqlserver_audit_bucket.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = "${aws_s3_bucket.sqlserver_audit_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_sqlserver_audit_s3_policy_attachment" {
  role       = aws_iam_role.rds_sqlserver_audit_role.name
  policy_arn = aws_iam_policy.rds_sqlserver_audit_s3_policy.arn
}

resource "aws_db_option_group" "option_group_pike" {
  name                     = "option-group-pike"
  option_group_description = "Option group for SQL Server Enterprise Edition with SQLSERVER_AUDIT and TDE"
  engine_name              = "sqlserver-ee"
  major_engine_version     = "11.00"

  option {
    option_name = "SQLSERVER_AUDIT"

    option_settings {
      name  = "IAM_ROLE_ARN"
      value = aws_iam_role.rds_sqlserver_audit_role.arn
    }

    option_settings {
      name  = "S3_BUCKET_ARN"
      value = aws_s3_bucket.sqlserver_audit_bucket.arn
    }
  }

  option {
    option_name = "TDE"
  }

  tags = {
    Name        = "option-group-pike"
    Environment = "example"
  }

  depends_on = [
    aws_iam_role_policy_attachment.rds_sqlserver_audit_s3_policy_attachment,
    aws_s3_bucket_public_access_block.sqlserver_audit_bucket,
    aws_s3_bucket_server_side_encryption_configuration.sqlserver_audit_bucket
  ]
}