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
  description = "AWS region where the Glacier vault and SNS topic will be created."
  type        = string
  default     = "us-east-1"
}

variable "glacier_vault_name" {
  description = "Name of the S3 Glacier vault."
  type        = string
  default     = "archive-retrieval-notification-vault"
}

variable "sns_topic_name" {
  description = "Name of the SNS topic for Glacier notifications."
  type        = string
  default     = "glacier-archive-retrieval-completed-topic"
}

data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "glacier_notifications" {
  name = var.sns_topic_name
}

resource "aws_sns_topic_policy" "glacier_publish_policy" {
  arn = aws_sns_topic.glacier_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGlacierToPublishNotifications"
        Effect = "Allow"
        Principal = {
          Service = "glacier.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.glacier_notifications.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_glacier_vault" "archive_vault" {
  name = var.glacier_vault_name

  notification {
    sns_topic = aws_sns_topic.glacier_notifications.arn
    events    = ["ArchiveRetrievalCompleted"]
  }

  depends_on = [
    aws_sns_topic_policy.glacier_publish_policy
  ]
}

output "glacier_vault_name" {
  description = "Name of the created Glacier vault."
  value       = aws_glacier_vault.archive_vault.name
}

output "glacier_vault_arn" {
  description = "ARN of the created Glacier vault."
  value       = aws_glacier_vault.archive_vault.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic receiving Glacier retrieval completion notifications."
  value       = aws_sns_topic.glacier_notifications.arn
}