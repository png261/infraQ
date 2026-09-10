resource "aws_efs_file_system" "this" {
  encrypted = true

  tags = {
    Name = "benchmark-efs"
  }
}

data "aws_iam_policy_document" "efs" {
  statement {
    sid    = "AllowAccountRootClientAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
    ]

    resources = [aws_efs_file_system.this.arn]

    condition {
      test     = "Bool"
      variable = "elasticfilesystem:AccessedViaMountTarget"
      values   = ["true"]
    }
  }
}

resource "aws_efs_file_system_policy" "this" {
  file_system_id = aws_efs_file_system.this.id
  policy         = data.aws_iam_policy_document.efs.json
}
