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

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "sqlserver_audit" {
  bucket = "option-group-pike-sqlserver-audit-${random_id.suffix.hex}"

  tags = {
    Name = "option-group-pike-sqlserver-audit"
  }
}

resource "aws_s3_bucket_public_access_block" "sqlserver_audit" {
  bucket = aws_s3_bucket.sqlserver_audit.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sqlserver_audit" {
  bucket = aws_s3_bucket.sqlserver_audit.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role" "rds_sqlserver_audit" {
  name = "option-group-pike-rds-sqlserver-audit-role"

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
}

resource "aws_iam_policy" "rds_sqlserver_audit" {
  name        = "option-group-pike-rds-sqlserver-audit-policy"
  description = "Allows RDS SQL Server Audit to write audit files to S3."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.sqlserver_audit.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.sqlserver_audit.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_sqlserver_audit" {
  role       = aws_iam_role.rds_sqlserver_audit.name
  policy_arn = aws_iam_policy.rds_sqlserver_audit.arn
}

resource "aws_db_option_group" "option_group_pike" {
  name                     = "option-group-pike"
  option_group_description = "Option group for SQL Server Enterprise Edition with SQLSERVER_AUDIT and TDE enabled."
  engine_name              = "sqlserver-ee"
  major_engine_version     = "11.00"

  option {
    option_name = "SQLSERVER_AUDIT"

    option_settings {
      name  = "IAM_ROLE_ARN"
      value = aws_iam_role.rds_sqlserver_audit.arn
    }

    option_settings {
      name  = "S3_BUCKET_ARN"
      value = aws_s3_bucket.sqlserver_audit.arn
    }
  }

  option {
    option_name = "TDE"
  }

  depends_on = [
    aws_iam_role_policy_attachment.rds_sqlserver_audit,
    aws_s3_bucket_public_access_block.sqlserver_audit,
    aws_s3_bucket_server_side_encryption_configuration.sqlserver_audit
  ]

  tags = {
    Name = "option-group-pike"
  }
}

output "rds_option_group_name" {
  value = aws_db_option_group.option_group_pike.name
}

output "sqlserver_audit_bucket_name" {
  value = aws_s3_bucket.sqlserver_audit.bucket
}

output "sqlserver_audit_role_arn" {
  value = aws_iam_role.rds_sqlserver_audit.arn
}