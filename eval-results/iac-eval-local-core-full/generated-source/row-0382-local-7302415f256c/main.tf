resource "aws_sns_topic" "glacier_notifications" {
  name = "glacier-vault-notifications"
}

resource "aws_glacier_vault" "example" {
  name = "example-glacier-vault"

  notification {
    events    = ["ArchiveRetrievalCompleted", "InventoryRetrievalCompleted"]
    sns_topic = aws_sns_topic.glacier_notifications.arn
  }
}
