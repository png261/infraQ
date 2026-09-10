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

resource "aws_secretsmanager_secret" "proxy_credentials" {
  name                    = var.proxy_credentials_secret_name
  description             = "Example proxy credentials for the Amazon Kendra web crawler data source."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "proxy_credentials" {
  secret_id = aws_secretsmanager_secret.proxy_credentials.id
  secret_string = jsonencode({
    username = var.proxy_username
    password = var.proxy_password
  })
}

resource "aws_iam_role" "kendra" {
  name = var.kendra_role_name

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
  name = "${var.kendra_role_name}-policy"
  role = aws_iam_role.kendra.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KendraCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "KendraProxyCredentials"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.proxy_credentials.arn
      }
    ]
  })
}

resource "aws_kendra_index" "this" {
  name     = var.kendra_index_name
  role_arn = aws_iam_role.kendra.arn
  edition  = "DEVELOPER_EDITION"

  depends_on = [aws_iam_role_policy.kendra]
}

resource "aws_kendra_data_source" "this" {
  name     = var.kendra_data_source_name
  index_id = aws_kendra_index.this.id
  role_arn = aws_iam_role.kendra.arn
  type     = "WEBCRAWLER"

  configuration {
    web_crawler_configuration {
      urls {
        seed_url_configuration {
          seed_urls = var.seed_urls
        }
      }

      proxy_configuration {
        host        = var.proxy_host
        port        = var.proxy_port
        credentials = aws_secretsmanager_secret.proxy_credentials.arn
      }
    }
  }

  depends_on = [
    aws_iam_role_policy.kendra,
    aws_secretsmanager_secret_version.proxy_credentials
  ]
}
