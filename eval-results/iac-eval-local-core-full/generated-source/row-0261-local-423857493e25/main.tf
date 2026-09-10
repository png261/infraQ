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

resource "aws_iam_group" "basic" {
  name = "basic-iam-group"
}

resource "aws_iam_user" "user_one" {
  name = "basic-iam-user-one"
}

resource "aws_iam_user" "user_two" {
  name = "basic-iam-user-two"
}

resource "aws_iam_group_membership" "basic" {
  name = "basic-iam-group-membership"

  users = [
    aws_iam_user.user_one.name,
    aws_iam_user.user_two.name,
  ]

  group = aws_iam_group.basic.name
}
