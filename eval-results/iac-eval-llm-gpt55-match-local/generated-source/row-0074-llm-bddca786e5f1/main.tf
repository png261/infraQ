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
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "kendra_index_name" {
  description = "Name of the Amazon Kendra index."
  type        = string
  default     = "example-kendra-index"
}

variable "kendra_data_source_name" {
  description = "Name of the Amazon Kendra data source."
  type        = string
  default     = "example-kendra-webcrawler-data-source"
}

variable "seed_url" {
  description = "Seed URL for the Kendra web crawler data source."
  type        = string
  default     = "https://example.com"
}

variable "proxy_host" {
  description = "Proxy host used by the Kendra web crawler."
  type        = string
  default     = "proxy.example.com"
}

variable "proxy_port" {
  description = "Proxy port used by the Kendra web crawler."
  type        = number
  default     = 8080
}

variable "proxy_username" {
  description = "Username for proxy authentication."
  type        = string
  default     = "proxy-user"
  sensitive   = true
}

variable "proxy_password" {
  description = "Password for proxy authentication."
  type        = string
  default     = "proxy-password"
  sensitive   = true
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

resource "aws_iam_role" "kendra_index_role" {
  name = "example-kendra-index-role"

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

resource "aws_iam_role_policy" "kendra_index_policy" {
  name = "example-kendra-index-policy"
  role = aws_iam_role.kendra_index_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "AWS/Kendra"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kendra/*"
      }
    ]
  })
}

resource "aws_kendra_index" "example" {
  name        = var.kendra_index_name
  description = "Example Amazon Kendra index for a web crawler data source with proxy configuration."
  edition     = "DEVELOPER_EDITION"
  role_arn    = aws_iam_role.kendra_index_role.arn

  depends_on = [
    aws_iam_role_policy.kendra_index_policy
  ]
}

resource "aws_secretsmanager_secret" "proxy_credentials" {
  name        = "example-kendra-proxy-credentials"
  description = "Proxy credentials used by the Kendra web crawler data source."
}

resource "aws_secretsmanager_secret_version" "proxy_credentials" {
  secret_id = aws_secretsmanager_secret.proxy_credentials.id

  secret_string = jsonencode({
    username = var.proxy_username
    password = var.proxy_password
  })
}

resource "aws_iam_role" "kendra_data_source_role" {
  name = "example-kendra-data-source-role"

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

resource "aws_iam_role_policy" "kendra_data_source_policy" {
  name = "example-kendra-data-source-policy"
  role = aws_iam_role.kendra_data_source_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kendra:BatchPutDocument",
          "kendra:BatchDeleteDocument"
        ]
        Resource = aws_kendra_index.example.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.proxy_credentials.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "AWS/Kendra"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kendra/*"
      }
    ]
  })
}

resource "aws_kendra_data_source" "webcrawler_with_proxy" {
  name        = var.kendra_data_source_name
  description = "Example Kendra web crawler data source configured to use an HTTP proxy."
  index_id    = aws_kendra_index.example.id
  type        = "WEBCRAWLER"
  role_arn    = aws_iam_role.kendra_data_source_role.arn
  language_code = "en"

  configuration {
    web_crawler_configuration {
      urls {
        seed_url_configuration {
          seed_urls = [
            var.seed_url
          ]

          web_crawler_mode = "HOST_ONLY"
        }
      }

      proxy_configuration {
        host        = var.proxy_host
        port        = var.proxy_port
        credentials = aws_secretsmanager_secret.proxy_credentials.arn
      }

      crawl_depth = 2

      max_content_size_per_page_in_mega_bytes = 50
      max_links_per_page                     = 100
      max_urls_per_minute_crawl_rate          = 100

      url_inclusion_patterns = [
        ".*"
      ]
    }
  }

  depends_on = [
    aws_iam_role_policy.kendra_data_source_policy,
    aws_secretsmanager_secret_version.proxy_credentials
  ]
}

output "kendra_index_id" {
  description = "ID of the created Kendra index."
  value       = aws_kendra_index.example.id
}

output "kendra_data_source_id" {
  description = "ID of the created Kendra data source."
  value       = aws_kendra_data_source.webcrawler_with_proxy.id
}

output "proxy_secret_arn" {
  description = "ARN of the Secrets Manager secret containing proxy credentials."
  value       = aws_secretsmanager_secret.proxy_credentials.arn
}