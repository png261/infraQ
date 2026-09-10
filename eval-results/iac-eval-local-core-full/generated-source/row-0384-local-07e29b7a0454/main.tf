data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "glacier_vault_access" {
  statement {
    sid    = "AllowAccountGlacierVaultAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions = [
      "glacier:DescribeVault",
      "glacier:ListJobs",
      "glacier:ListMultipartUploads",
    ]

    resources = [
      "arn:aws:glacier:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:vaults/iac-eval-glacier-vault",
    ]
  }
}

resource "aws_glacier_vault" "this" {
  name          = "iac-eval-glacier-vault"
  access_policy = data.aws_iam_policy_document.glacier_vault_access.json
}

output "glacier_vault_name" {
  description = "Name of the S3 Glacier vault."
  value       = aws_glacier_vault.this.name
}
