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

variable "vault_name" {
  description = "Name of the S3 Glacier vault."
  type        = string
  default     = "example-glacier-vault-with-lock"
}

variable "minimum_retention_days" {
  description = "Minimum number of days archives must be retained before they can be deleted."
  type        = number
  default     = 365
}

variable "complete_vault_lock" {
  description = "Whether to permanently complete the Glacier Vault Lock. WARNING: This is irreversible."
  type        = bool
  default     = false
}

data "aws_caller_identity" "current" {}

resource "aws_glacier_vault" "this" {
  name = var.vault_name

  tags = {
    Name        = var.vault_name
    Environment = "example"
    ManagedBy   = "terraform"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_glacier_vault_lock" "this" {
  vault_name    = aws_glacier_vault.this.name
  complete_lock = var.complete_vault_lock

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyArchiveDeletionBeforeMinimumRetention"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "glacier:DeleteArchive"
        ]
        Resource = "arn:aws:glacier:${var.aws_region}:${data.aws_caller_identity.current.account_id}:vaults/${aws_glacier_vault.this.name}"
        Condition = {
          NumericLessThan = {
            "glacier:ArchiveAgeInDays" = var.minimum_retention_days
          }
        }
      }
    ]
  })
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
  description = "Whether the Glacier Vault Lock has been permanently completed."
  value       = var.complete_vault_lock
}