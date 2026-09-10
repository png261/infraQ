data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "kendra" {
  name = "basic-kendra-index-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "kendra.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "kendra" {
  name = "basic-kendra-index-policy"
  role = aws_iam_role.kendra.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowKendraCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/kendra/*"
        ]
      }
    ]
  })
}

resource "aws_kendra_index" "basic" {
  name        = "basic-kendra-index"
  description = "Basic Amazon Kendra index with user group resolution configuration."
  edition     = "DEVELOPER_EDITION"
  role_arn    = aws_iam_role.kendra.arn

  user_group_resolution_configuration {
    user_group_resolution_mode = "AWS_SSO"
  }

  depends_on = [aws_iam_role_policy.kendra]
}
