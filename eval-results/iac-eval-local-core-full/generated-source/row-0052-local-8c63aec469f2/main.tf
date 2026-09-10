data "aws_iam_policy_document" "lex_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lexv2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lex_bot" {
  name               = "children-lexv2-bot-role"
  assume_role_policy = data.aws_iam_policy_document.lex_assume_role.json
}

resource "aws_lexv2models_bot" "children" {
  name                        = "children-lexv2-bot"
  role_arn                    = aws_iam_role.lex_bot.arn
  idle_session_ttl_in_seconds = 300

  data_privacy {
    child_directed = true
  }
}
