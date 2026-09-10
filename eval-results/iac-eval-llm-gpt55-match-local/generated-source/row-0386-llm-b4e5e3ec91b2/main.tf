terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the Glacier vault will be created."
  type        = string
  default     = "us-east-1"
}

variable "glacier_vault_name" {
  description = "Name of the S3 Glacier vault."
  type        = string
  default     = "example-locked-glacier-vault"
}

variable "archive_retention_days" {
  description = "Minimum archive age in days before archives can be deleted."
  type        = number
  default     = 365
}

variable "complete_vault_lock" {
  description = "Whether to complete the Glacier Vault Lock. WARNING: Once completed, the lock policy cannot be changed or removed."
  type        = bool
  default     = false
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_iam_policy_document" "vault_access_policy" {
  statement {
    sid    = "AllowAccountRootFullGlacierAccess"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
      ]
    }

    actions = [
      "glacier:*"
    ]

    resources = [
      aws_glacier_vault.this.arn
    ]
  }
}

data "aws_iam_policy_document" "vault_lock_policy" {
  statement {
    sid    = "DenyArchiveDeletionBeforeRetentionPeriod"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "glacier:DeleteArchive"
    ]

    resources = [
      "${aws_glacier_vault.this.arn}/archives/*"
    ]

    condition {
      test     = "NumericLessThan"
      variable = "glacier:ArchiveAgeInDays"
      values   = [tostring(var.archive_retention_days)]
    }
  }
}

resource "aws_glacier_vault" "this" {
  name          = var.glacier_vault_name
  access_policy = data.aws_iam_policy_document.vault_access_policy.json

  tags = {
    Name        = var.glacier_vault_name
    Environment = "example"
    ManagedBy   = "terraform"
  }
}

resource "aws_glacier_vault_lock" "this" {
  vault_name    = aws_glacier_vault.this.name
  policy        = data.aws_iam_policy_document.vault_lock_policy.json
  complete_lock = var.complete_vault_lock

  ignore_deletion_error = true
}

output "glacier_vault_name" {
  description = "Name of the created Glacier vault."
  value       = aws_glacier_vault.this.name
}

output "glacier_vault_arn" {
  description = "ARN of the created Glacier vault."
  value       = aws_glacier_vault.this.arn
}

output "vault_lock_completed" {
  description = "Whether the Glacier Vault Lock was completed."
  value       = var.complete_vault_lock
}