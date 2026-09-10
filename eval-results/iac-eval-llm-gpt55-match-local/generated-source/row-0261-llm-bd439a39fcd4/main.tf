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

resource "aws_iam_user" "basic_user_1" {
  name = "basic-user-1"

  tags = {
    Name        = "basic-user-1"
    Environment = "basic"
  }
}

resource "aws_iam_user" "basic_user_2" {
  name = "basic-user-2"

  tags = {
    Name        = "basic-user-2"
    Environment = "basic"
  }
}

resource "aws_iam_group" "basic_group" {
  name = "basic-iam-group"
}

resource "aws_iam_group_membership" "basic_group_membership" {
  name = "basic-iam-group-membership"

  users = [
    aws_iam_user.basic_user_1.name,
    aws_iam_user.basic_user_2.name
  ]

  group = aws_iam_group.basic_group.name
}

resource "aws_iam_group_policy_attachment" "readonly_access" {
  group      = aws_iam_group.basic_group.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

output "iam_users" {
  description = "The IAM users created by this configuration."
  value = [
    aws_iam_user.basic_user_1.name,
    aws_iam_user.basic_user_2.name
  ]
}

output "iam_group" {
  description = "The IAM group created by this configuration."
  value       = aws_iam_group.basic_group.name
}