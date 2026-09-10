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
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where storage and backup resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name_prefix" {
  description = "Prefix for the long-term storage S3 bucket name."
  type        = string
  default     = "long-term-data-backup"
}

variable "backup_vault_name" {
  description = "Name of the AWS Backup vault."
  type        = string
  default     = "long-term-data-backup-vault"
}

variable "backup_plan_name" {
  description = "Name of the AWS Backup plan."
  type        = string
  default     = "long-term-data-backup-plan"
}

variable "backup_schedule" {
  description = "AWS Backup cron schedule. Default is daily at 5 AM UTC."
  type        = string
  default     = "cron(0 5 * * ? *)"
}

variable "backup_cold_storage_after_days" {
  description = "Number of days before AWS Backup recovery points move to cold storage."
  type        = number
  default     = 30
}

variable "backup_delete_after_days" {
  description = "Number of days before AWS Backup recovery points are deleted."
  type        = number
  default     = 3650
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "long_term_storage" {
  bucket        = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"
  force_destroy = false

  tags = {
    Name        = "Long Term Data and Backup Storage"
    Environment = "production"
    Purpose     = "long-term-storage-and-backup"
  }
}

resource "aws_s3_bucket_public_access_block" "long_term_storage" {
  bucket = aws_s3_bucket.long_term_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "long_term_storage" {
  bucket = aws_s3_bucket.long_term_storage.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "long_term_storage" {
  bucket = aws_s3_bucket.long_term_storage.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "long_term_storage" {
  bucket = aws_s3_bucket.long_term_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "long_term_storage" {
  bucket = aws_s3_bucket.long_term_storage.id

  rule {
    id     = "long-term-archive-lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "GLACIER_IR"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 180
      storage_class = "DEEP_ARCHIVE"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = 180
      storage_class   = "DEEP_ARCHIVE"
    }

    noncurrent_version_expiration {
      noncurrent_days = 3650
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.long_term_storage
  ]
}

resource "aws_backup_vault" "long_term_backup_vault" {
  name = var.backup_vault_name

  tags = {
    Name        = var.backup_vault_name
    Environment = "production"
    Purpose     = "long-term-backup-vault"
  }
}

resource "aws_iam_role" "aws_backup_role" {
  name = "aws-backup-s3-long-term-role-${random_id.bucket_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name    = "AWS Backup S3 Long Term Role"
    Purpose = "s3-backup"
  }
}

resource "aws_iam_role_policy_attachment" "backup_s3_backup_policy" {
  role       = aws_iam_role.aws_backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup"
}

resource "aws_iam_role_policy_attachment" "backup_s3_restore_policy" {
  role       = aws_iam_role.aws_backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore"
}

resource "aws_backup_plan" "long_term_backup_plan" {
  name = var.backup_plan_name

  rule {
    rule_name         = "daily-long-term-s3-backup"
    target_vault_name = aws_backup_vault.long_term_backup_vault.name
    schedule          = var.backup_schedule

    lifecycle {
      cold_storage_after = var.backup_cold_storage_after_days
      delete_after       = var.backup_delete_after_days
    }

    recovery_point_tags = {
      BackupType  = "daily"
      Retention   = "long-term"
      StorageType = "s3"
    }
  }

  tags = {
    Name        = var.backup_plan_name
    Environment = "production"
    Purpose     = "daily-long-term-s3-backup"
  }
}

resource "aws_backup_selection" "s3_bucket_backup_selection" {
  name         = "long-term-s3-bucket-selection"
  iam_role_arn = aws_iam_role.aws_backup_role.arn
  plan_id      = aws_backup_plan.long_term_backup_plan.id

  resources = [
    aws_s3_bucket.long_term_storage.arn
  ]

  depends_on = [
    aws_iam_role_policy_attachment.backup_s3_backup_policy,
    aws_iam_role_policy_attachment.backup_s3_restore_policy
  ]
}

output "s3_bucket_name" {
  description = "Name of the long-term storage S3 bucket."
  value       = aws_s3_bucket.long_term_storage.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the long-term storage S3 bucket."
  value       = aws_s3_bucket.long_term_storage.arn
}

output "backup_vault_name" {
  description = "Name of the AWS Backup vault."
  value       = aws_backup_vault.long_term_backup_vault.name
}

output "backup_plan_id" {
  description = "ID of the AWS Backup plan."
  value       = aws_backup_plan.long_term_backup_plan.id
}