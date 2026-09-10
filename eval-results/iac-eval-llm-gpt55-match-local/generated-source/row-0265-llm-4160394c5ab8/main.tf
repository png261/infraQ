terraform {
  required_version = ">= 1.0.0"

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

resource "aws_iam_user" "basic_user" {
  name = "basic-example-user"

  tags = {
    Name        = "basic-example-user"
    Environment = "example"
  }
}

resource "aws_iam_group" "basic_group" {
  name = "basic-example-group"
}

resource "aws_iam_policy" "basic_read_only_policy" {
  name        = "basic-example-read-only-policy"
  description = "A basic read-only IAM policy for example purposes"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:GetUser",
          "iam:ListUsers",
          "iam:ListGroups",
          "iam:ListPolicies",
          "iam:GetAccountSummary"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_group_policy_attachment" "basic_group_policy_attachment" {
  group      = aws_iam_group.basic_group.name
  policy_arn = aws_iam_policy.basic_read_only_policy.arn
}

resource "aws_iam_user_group_membership" "basic_user_membership" {
  user = aws_iam_user.basic_user.name

  groups = [
    aws_iam_group.basic_group.name
  ]
}

output "iam_user_name" {
  description = "The name of the IAM user"
  value       = aws_iam_user.basic_user.name
}

output "iam_user_arn" {
  description = "The ARN of the IAM user"
  value       = aws_iam_user.basic_user.arn
}

output "iam_group_name" {
  description = "The name of the IAM group"
  value       = aws_iam_group.basic_group.name
}