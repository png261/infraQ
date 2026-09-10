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
  description = "AWS region where the Kendra index will be created."
  type        = string
  default     = "us-east-1"
}

variable "kendra_index_name" {
  description = "Name of the Amazon Kendra index."
  type        = string
  default     = "basic-kendra-index"
}

resource "aws_iam_role" "kendra_index_role" {
  name = "basic-kendra-index-role"

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
  name = "basic-kendra-index-policy"
  role = aws_iam_role.kendra_index_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchLogs"
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
        Sid    = "AllowCloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kendra_index" "basic" {
  name        = var.kendra_index_name
  description = "Basic Amazon Kendra index with user group resolution configuration."
  edition     = "DEVELOPER_EDITION"
  role_arn    = aws_iam_role.kendra_index_role.arn

  user_context_policy = "ATTRIBUTE_FILTER"

  user_group_resolution_configuration {
    user_group_resolution_mode = "NONE"
  }

  tags = {
    Name        = var.kendra_index_name
    Environment = "development"
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_iam_role_policy.kendra_index_policy
  ]
}

output "kendra_index_id" {
  description = "The ID of the Amazon Kendra index."
  value       = aws_kendra_index.basic.id
}

output "kendra_index_arn" {
  description = "The ARN of the Amazon Kendra index."
  value       = aws_kendra_index.basic.arn
}

output "kendra_index_role_arn" {
  description = "The ARN of the IAM role used by the Kendra index."
  value       = aws_iam_role.kendra_index_role.arn
}