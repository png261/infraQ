data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "glacier_publish_to_sns" {
  statement {
    sid    = "AllowGlacierPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["glacier.amazonaws.com"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.glacier_notifications.arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic" "glacier_notifications" {
  name = "glacier-vault-notifications"
}

resource "aws_sns_topic_policy" "glacier_notifications" {
  arn    = aws_sns_topic.glacier_notifications.arn
  policy = data.aws_iam_policy_document.glacier_publish_to_sns.json
}

resource "aws_glacier_vault" "example" {
  name = "example-glacier-vault"

  notification {
    events    = ["ArchiveRetrievalCompleted", "InventoryRetrievalCompleted"]
    sns_topic = aws_sns_topic.glacier_notifications.arn
  }
}
