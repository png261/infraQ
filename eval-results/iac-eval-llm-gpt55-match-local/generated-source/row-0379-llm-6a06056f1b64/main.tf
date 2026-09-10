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
  default     = "long-term-archive-vault"
}

variable "iam_role_name" {
  description = "Name of the IAM role for Glacier vault access."
  type        = string
  default     = "glacier-archive-access-role"
}

data "aws_caller_identity" "current" {}

resource "aws_glacier_vault" "archive" {
  name = var.vault_name

  tags = {
    Name        = var.vault_name
    Environment = "archive"
    Purpose     = "long-term-data-archiving"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role" "glacier_access_role" {
  name = var.iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name      = var.iam_role_name
    ManagedBy = "terraform"
  }
}

resource "aws_iam_policy" "glacier_access_policy" {
  name        = "${var.vault_name}-access-policy"
  description = "IAM policy allowing access to the Glacier archive vault."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGlacierVaultAccess"
        Effect = "Allow"
        Action = [
          "glacier:DescribeVault",
          "glacier:GetVaultAccessPolicy",
          "glacier:GetVaultLock",
          "glacier:GetVaultNotifications",
          "glacier:ListJobs",
          "glacier:ListMultipartUploads",
          "glacier:ListParts",
          "glacier:UploadArchive",
          "glacier:InitiateMultipartUpload",
          "glacier:UploadMultipartPart",
          "glacier:CompleteMultipartUpload",
          "glacier:AbortMultipartUpload",
          "glacier:InitiateJob",
          "glacier:DescribeJob",
          "glacier:GetJobOutput",
          "glacier:DeleteArchive"
        ]
        Resource = aws_glacier_vault.archive.arn
      }
    ]
  })

  tags = {
    Name      = "${var.vault_name}-access-policy"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "glacier_access_attach" {
  role       = aws_iam_role.glacier_access_role.name
  policy_arn = aws_iam_policy.glacier_access_policy.arn
}

output "glacier_vault_name" {
  description = "Name of the created S3 Glacier vault."
  value       = aws_glacier_vault.archive.name
}

output "glacier_vault_arn" {
  description = "ARN of the created S3 Glacier vault."
  value       = aws_glacier_vault.archive.arn
}

output "glacier_access_role_arn" {
  description = "ARN of the IAM role with access to the Glacier vault."
  value       = aws_iam_role.glacier_access_role.arn
}