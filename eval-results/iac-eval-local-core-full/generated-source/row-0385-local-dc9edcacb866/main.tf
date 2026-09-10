resource "aws_glacier_vault" "this" {
  name = "benchmark-glacier-vault"
}

data "aws_iam_policy_document" "vault_lock" {
  statement {
    sid    = "DenyDeleteArchivesForCompliance"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "glacier:DeleteArchive",
    ]

    resources = [
      aws_glacier_vault.this.arn,
    ]
  }
}

resource "aws_glacier_vault_lock" "this" {
  vault_name  = aws_glacier_vault.this.name
  policy      = data.aws_iam_policy_document.vault_lock.json
  complete_lock = false
}
