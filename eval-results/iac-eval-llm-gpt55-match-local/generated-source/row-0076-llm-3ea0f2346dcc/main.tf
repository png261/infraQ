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
  default     = "basic-kendra-index"
}

variable "kendra_index_edition" {
  description = "Edition of the Amazon Kendra index."
  type        = string
  default     = "DEVELOPER_EDITION"
}

resource "aws_iam_role" "kendra_role" {
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

resource "aws_iam_role_policy" "kendra_policy" {
  name = "basic-kendra-index-policy"
  role = aws_iam_role.kendra_role.id

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
      }
    ]
  })
}

resource "aws_kendra_index" "basic" {
  name        = var.kendra_index_name
  description = "Basic Amazon Kendra index with default document metadata configuration updates."
  edition     = var.kendra_index_edition
  role_arn    = aws_iam_role.kendra_role.arn

  document_metadata_configuration_updates {
    name = "department"
    type = "STRING_VALUE"

    search {
      displayable = true
      facetable   = true
      searchable  = true
      sortable    = false
    }
  }

  tags = {
    Name        = var.kendra_index_name
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

output "kendra_index_id" {
  description = "The ID of the Amazon Kendra index."
  value       = aws_kendra_index.basic.id
}

output "kendra_index_arn" {
  description = "The ARN of the Amazon Kendra index."
  value       = aws_kendra_index.basic.arn
}

output "kendra_role_arn" {
  description = "The ARN of the IAM role used by Amazon Kendra."
  value       = aws_iam_role.kendra_role.arn
}