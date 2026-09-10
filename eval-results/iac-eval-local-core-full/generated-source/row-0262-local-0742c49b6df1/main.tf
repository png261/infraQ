terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_iam_policy_document" "group_policy" {
  statement {
    effect = "Allow"

    actions = [
      "iam:GetAccountSummary",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_group" "example" {
  name = "example-group"
}

resource "aws_iam_policy" "example" {
  name   = "example-group-policy"
  policy = data.aws_iam_policy_document.group_policy.json
}

resource "aws_iam_group_policy_attachment" "example" {
  group      = aws_iam_group.example.name
  policy_arn = aws_iam_policy.example.arn
}
