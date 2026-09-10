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

resource "aws_iam_role" "kendra" {
  name = "iac-eval-kendra-role"

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
  name = "iac-eval-kendra-policy"
  role = aws_iam_role.kendra.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KendraIndexAccess"
        Effect = "Allow"
        Action = [
          "kendra:BatchDeleteDocument",
          "kendra:BatchPutDocument",
          "kendra:DescribeDataSource",
          "kendra:DescribeIndex",
          "kendra:ListDataSources"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kendra_index" "example" {
  name     = "iac-eval-kendra-index"
  edition  = "DEVELOPER_EDITION"
  role_arn = aws_iam_role.kendra.arn

  depends_on = [aws_iam_role_policy.kendra]
}

resource "aws_kendra_data_source" "web" {
  name     = "iac-eval-kendra-web-source"
  index_id = aws_kendra_index.example.id
  role_arn = aws_iam_role.kendra.arn
  type     = "WEBCRAWLER"

  configuration {
    web_crawler_configuration {
      url_exclusion_patterns = [
        "https://example.com/private/.*",
        "https://example.com/archive/.*"
      ]

      url_inclusion_patterns = [
        "https://example.com/docs/.*",
        "https://example.com/blog/.*"
      ]

      urls {
        seed_url_configuration {
          seed_urls = [
            "https://example.com/docs/",
            "https://example.com/blog/"
          ]

          web_crawler_mode = "EVERYTHING"
        }
      }
    }
  }

  depends_on = [aws_iam_role_policy.kendra]
}
