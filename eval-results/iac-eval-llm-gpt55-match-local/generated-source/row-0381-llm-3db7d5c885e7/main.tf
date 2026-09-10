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
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "glacier_vault_name" {
  description = "Name of the S3 Glacier vault."
  type        = string
  default     = "example-glacier-vault"
}

variable "dlm_policy_name" {
  description = "Name of the AWS Data Lifecycle Manager policy."
  type        = string
  default     = "example-ebs-snapshot-dlm-policy"
}

variable "ebs_volume_size" {
  description = "Size of the demo EBS volume in GiB."
  type        = number
  default     = 8
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_glacier_vault" "archive_vault" {
  name = var.glacier_vault_name

  tags = {
    Name        = var.glacier_vault_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

resource "aws_ebs_volume" "dlm_target_volume" {
  availability_zone = data.aws_availability_zones.available.names[0]
  size              = var.ebs_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name        = "dlm-target-ebs-volume"
    Environment = "demo"
    Backup      = "dlm"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role" "dlm_role" {
  name = "example-dlm-lifecycle-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "dlm.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name      = "example-dlm-lifecycle-role"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy" "dlm_policy" {
  name = "example-dlm-lifecycle-policy"
  role = aws_iam_role.dlm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:CreateSnapshots",
          "ec2:DeleteSnapshot",
          "ec2:DescribeVolumes",
          "ec2:DescribeInstances",
          "ec2:DescribeSnapshots",
          "ec2:DescribeTags",
          "ec2:CreateTags",
          "ec2:CopySnapshot",
          "ec2:ModifySnapshotAttribute",
          "ec2:DescribeSnapshotAttribute"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_dlm_lifecycle_policy" "ebs_snapshot_policy" {
  description        = "Creates scheduled EBS snapshots for volumes tagged Backup=dlm."
  execution_role_arn = aws_iam_role.dlm_role.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    target_tags = {
      Backup = "dlm"
    }

    schedule {
      name = "daily-ebs-snapshot-schedule"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]
      }

      retain_rule {
        count = 7
      }

      copy_tags = true

      tags_to_add = {
        CreatedBy   = "AWS Data Lifecycle Manager"
        Environment = "demo"
      }
    }
  }

  tags = {
    Name      = var.dlm_policy_name
    ManagedBy = "terraform"
  }

  depends_on = [
    aws_iam_role_policy.dlm_policy
  ]
}

output "glacier_vault_name" {
  description = "Name of the created S3 Glacier vault."
  value       = aws_glacier_vault.archive_vault.name
}

output "glacier_vault_arn" {
  description = "ARN of the created S3 Glacier vault."
  value       = aws_glacier_vault.archive_vault.arn
}

output "dlm_policy_id" {
  description = "ID of the AWS Data Lifecycle Manager policy."
  value       = aws_dlm_lifecycle_policy.ebs_snapshot_policy.id
}

output "dlm_policy_arn" {
  description = "ARN of the AWS Data Lifecycle Manager policy."
  value       = aws_dlm_lifecycle_policy.ebs_snapshot_policy.arn
}

output "dlm_target_ebs_volume_id" {
  description = "ID of the EBS volume targeted by the DLM policy."
  value       = aws_ebs_volume.dlm_target_volume.id
}