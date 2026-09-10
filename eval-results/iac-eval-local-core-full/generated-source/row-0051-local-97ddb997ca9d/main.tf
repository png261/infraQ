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

data "aws_iam_policy_document" "lex_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lexv2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lex_bot" {
  name               = "iac-eval-lexv2-bot-role"
  assume_role_policy = data.aws_iam_policy_document.lex_assume_role.json
}

resource "aws_lexv2models_bot" "example" {
  name                        = "iac-eval-lexv2-bot"
  role_arn                    = aws_iam_role.lex_bot.arn
  idle_session_ttl_in_seconds = 300

  data_privacy {
    child_directed = false
  }
}
