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

data "aws_caller_identity" "current" {}

locals {
  vault_name = "iac-eval-glacier-vault"
  vault_arn  = "arn:aws:glacier:us-east-1:${data.aws_caller_identity.current.account_id}:vaults/${local.vault_name}"
}

resource "aws_glacier_vault" "this" {
  name = local.vault_name

  access_policy = data.aws_iam_policy_document.glacier_vault_access.json
}

data "aws_iam_policy_document" "glacier_vault_access" {
  statement {
    sid    = "AllowCurrentAccountVaultAccess"
    effect = "Allow"

    actions = [
      "glacier:DescribeVault",
      "glacier:GetVaultAccessPolicy",
      "glacier:GetVaultLock",
      "glacier:ListJobs",
      "glacier:ListMultipartUploads",
      "glacier:ListParts",
      "glacier:ListTagsForVault",
    ]

    resources = [local.vault_arn]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_glacier_vault_lock" "this" {
  vault_name    = aws_glacier_vault.this.name
  complete_lock = true
  policy        = data.aws_iam_policy_document.glacier_vault_access.json
}
