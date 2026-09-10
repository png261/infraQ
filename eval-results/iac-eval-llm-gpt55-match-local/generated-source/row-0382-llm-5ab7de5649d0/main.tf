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
  default     = "example-glacier-vault"
}

variable "sns_topic_name" {
  description = "Name of the SNS topic used for Glacier notifications."
  type        = string
  default     = "glacier-vault-notifications"
}

data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "glacier_notifications" {
  name = var.sns_topic_name

  tags = {
    Name        = var.sns_topic_name
    Environment = "example"
    ManagedBy   = "terraform"
  }
}

data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    sid    = "AllowGlacierPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["glacier.amazonaws.com"]
    }

    actions = [
      "SNS:Publish"
    ]

    resources = [
      aws_sns_topic.glacier_notifications.arn
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "glacier_notifications_policy" {
  arn    = aws_sns_topic.glacier_notifications.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

resource "aws_glacier_vault" "main" {
  name = var.glacier_vault_name

  notification {
    sns_topic = aws_sns_topic.glacier_notifications.arn

    events = [
      "ArchiveRetrievalCompleted",
      "InventoryRetrievalCompleted"
    ]
  }

  access_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "glacier:*"
        Resource = "arn:aws:glacier:${var.aws_region}:${data.aws_caller_identity.current.account_id}:vaults/${var.glacier_vault_name}"
      }
    ]
  })

  tags = {
    Name        = var.glacier_vault_name
    Environment = "example"
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_sns_topic_policy.glacier_notifications_policy
  ]
}

output "glacier_vault_name" {
  description = "Name of the created Glacier vault."
  value       = aws_glacier_vault.main.name
}

output "glacier_vault_arn" {
  description = "ARN of the created Glacier vault."
  value       = aws_glacier_vault.main.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic used for Glacier notifications."
  value       = aws_sns_topic.glacier_notifications.arn
}