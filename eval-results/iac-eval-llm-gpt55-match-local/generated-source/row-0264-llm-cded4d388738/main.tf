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

resource "aws_iam_group" "basic_group" {
  name = "example-basic-iam-group"
  path = "/"
}

resource "aws_iam_user" "user_one" {
  name          = "example-basic-user-one"
  path          = "/"
  force_destroy = true
}

resource "aws_iam_user" "user_two" {
  name          = "example-basic-user-two"
  path          = "/"
  force_destroy = true
}

resource "aws_iam_group_membership" "basic_group_membership" {
  name = "example-basic-group-membership"

  users = [
    aws_iam_user.user_one.name,
    aws_iam_user.user_two.name
  ]

  group = aws_iam_group.basic_group.name
}

resource "aws_iam_group_policy_attachment" "readonly_access" {
  group      = aws_iam_group.basic_group.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

output "iam_group_name" {
  description = "The name of the IAM group."
  value       = aws_iam_group.basic_group.name
}

output "iam_group_users" {
  description = "The IAM users assigned to the group."
  value = [
    aws_iam_user.user_one.name,
    aws_iam_user.user_two.name
  ]
}

output "attached_policy_arn" {
  description = "The IAM policy attached to the group."
  value       = aws_iam_group_policy_attachment.readonly_access.policy_arn
}