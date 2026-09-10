resource "aws_sns_topic" "archive_retrieval_completed" {
  name = "glacier-archive-retrieval-completed"
}

resource "aws_glacier_vault" "archive_notifications" {
  name = "archive-retrieval-notifications"

  notification {
    sns_topic = aws_sns_topic.archive_retrieval_completed.arn
    events    = ["ArchiveRetrievalCompleted"]
  }
}
