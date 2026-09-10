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

resource "aws_iam_group" "example_group" {
  name = "example-iam-group"
  path = "/"
}

resource "aws_iam_policy" "example_policy" {
  name        = "example-s3-readonly-policy"
  description = "Example IAM policy granting read-only access to S3"
  path        = "/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListAllBuckets"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadBucketObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::*",
          "arn:aws:s3:::*/*"
        ]
      }
    ]
  })
}

resource "aws_iam_group_policy_attachment" "example_group_policy_attachment" {
  group      = aws_iam_group.example_group.name
  policy_arn = aws_iam_policy.example_policy.arn
}