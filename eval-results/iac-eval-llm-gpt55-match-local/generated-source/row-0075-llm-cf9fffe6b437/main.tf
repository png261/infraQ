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

variable "kendra_index_name" {
  description = "Name of the Amazon Kendra index."
  type        = string
  default     = "example-kendra-index"
}

variable "kendra_data_source_name" {
  description = "Name of the Amazon Kendra web crawler data source."
  type        = string
  default     = "example-webcrawler-data-source"
}

variable "seed_urls" {
  description = "Seed URLs for the Kendra web crawler."
  type        = list(string)
  default = [
    "https://docs.aws.amazon.com/kendra/latest/dg/"
  ]
}

variable "url_inclusion_patterns" {
  description = "Regex patterns for URLs that should be included by the crawler."
  type        = list(string)
  default = [
    "https://docs\\.aws\\.amazon\\.com/kendra/.*"
  ]
}

variable "url_exclusion_patterns" {
  description = "Regex patterns for URLs that should be excluded by the crawler."
  type        = list(string)
  default = [
    ".*\\/API_.*",
    ".*\\/images\\/.*",
    ".*\\/samples\\/.*"
  ]
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_iam_role" "kendra_index_role" {
  name = "kendra-index-role-example"

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

resource "aws_iam_policy" "kendra_index_policy" {
  name        = "kendra-index-policy-example"
  description = "Permissions required by Amazon Kendra index."

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
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kendra/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogStreams",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kendra/*:log-stream:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "kendra_index_policy_attachment" {
  role       = aws_iam_role.kendra_index_role.name
  policy_arn = aws_iam_policy.kendra_index_policy.arn
}

resource "aws_kendra_index" "example" {
  name        = var.kendra_index_name
  description = "Example Amazon Kendra index for web crawler data source."
  edition     = "DEVELOPER_EDITION"
  role_arn    = aws_iam_role.kendra_index_role.arn

  depends_on = [
    aws_iam_role_policy_attachment.kendra_index_policy_attachment
  ]
}

resource "aws_iam_role" "kendra_data_source_role" {
  name = "kendra-webcrawler-data-source-role-example"

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

resource "aws_iam_policy" "kendra_data_source_policy" {
  name        = "kendra-webcrawler-data-source-policy-example"
  description = "Permissions required by Amazon Kendra web crawler data source."

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
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kendra/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogStreams",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kendra/*:log-stream:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "kendra_data_source_policy_attachment" {
  role       = aws_iam_role.kendra_data_source_role.name
  policy_arn = aws_iam_policy.kendra_data_source_policy.arn
}

resource "aws_kendra_data_source" "webcrawler" {
  name        = var.kendra_data_source_name
  description = "Amazon Kendra web crawler data source with URL inclusion and exclusion patterns."
  index_id    = aws_kendra_index.example.id
  type        = "WEBCRAWLER"
  role_arn    = aws_iam_role.kendra_data_source_role.arn
  language_code = "en"

  configuration = jsonencode({
    WebCrawlerConfiguration = {
      Urls = {
        SeedUrlConfiguration = {
          SeedUrls       = var.seed_urls
          WebCrawlerMode = "HOST_ONLY"
        }
      }

      CrawlDepth                         = 2
      MaxLinksPerPage                    = 100
      MaxContentSizePerPageInMegaBytes   = 50
      MaxUrlsPerMinuteCrawlRate          = 300
      UrlInclusionPatterns               = var.url_inclusion_patterns
      UrlExclusionPatterns               = var.url_exclusion_patterns
    }
  })

  depends_on = [
    aws_iam_role_policy_attachment.kendra_data_source_policy_attachment
  ]
}

output "kendra_index_id" {
  description = "The ID of the Amazon Kendra index."
  value       = aws_kendra_index.example.id
}

output "kendra_index_arn" {
  description = "The ARN of the Amazon Kendra index."
  value       = aws_kendra_index.example.arn
}

output "kendra_data_source_id" {
  description = "The ID of the Amazon Kendra web crawler data source."
  value       = aws_kendra_data_source.webcrawler.id
}