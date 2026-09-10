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
  default     = "example-glacier-vault"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "glacier_vault_access_policy" {
  statement {
    sid    = "AllowCurrentAccountGlacierVaultAccess"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      ]
    }

    actions = [
      "glacier:AbortMultipartUpload",
      "glacier:CompleteMultipartUpload",
      "glacier:DeleteArchive",
      "glacier:DeleteVault",
      "glacier:DescribeVault",
      "glacier:GetJobOutput",
      "glacier:InitiateJob",
      "glacier:InitiateMultipartUpload",
      "glacier:ListJobs",
      "glacier:ListMultipartUploads",
      "glacier:ListParts",
      "glacier:UploadArchive",
      "glacier:UploadMultipartPart"
    ]

    resources = [
      "arn:aws:glacier:${var.aws_region}:${data.aws_caller_identity.current.account_id}:vaults/${var.glacier_vault_name}"
    ]
  }
}

resource "aws_glacier_vault" "this" {
  name          = var.glacier_vault_name
  access_policy = data.aws_iam_policy_document.glacier_vault_access_policy.json
}

output "glacier_vault_name" {
  description = "Name of the created Glacier vault."
  value       = aws_glacier_vault.this.name
}

output "glacier_vault_arn" {
  description = "ARN of the created Glacier vault."
  value       = aws_glacier_vault.this.arn
}