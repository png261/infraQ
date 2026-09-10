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
  description = "AWS region where the EFS file system will be created."
  type        = string
  default     = "us-east-1"
}

variable "efs_name" {
  description = "Name tag for the EFS file system."
  type        = string
  default     = "automatic-backup-efs"
}

resource "aws_efs_file_system" "this" {
  creation_token = var.efs_name
  encrypted      = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name        = var.efs_name
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_efs_backup_policy" "this" {
  file_system_id = aws_efs_file_system.this.id

  backup_policy {
    status = "ENABLED"
  }
}

output "efs_file_system_id" {
  description = "The ID of the created EFS file system."
  value       = aws_efs_file_system.this.id
}

output "efs_dns_name" {
  description = "The DNS name of the created EFS file system."
  value       = aws_efs_file_system.this.dns_name
}

output "efs_backup_policy_status" {
  description = "The backup policy status for the EFS file system."
  value       = aws_efs_backup_policy.this.backup_policy[0].status
}