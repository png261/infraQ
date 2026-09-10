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
  default     = "example-efs-file-system"
}

variable "environment" {
  description = "Environment tag for the EFS file system."
  type        = string
  default     = "dev"
}

resource "aws_efs_file_system" "this" {
  creation_token = var.efs_name

  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name        = var.efs_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

output "efs_file_system_id" {
  description = "The ID of the EFS file system."
  value       = aws_efs_file_system.this.id
}

output "efs_file_system_arn" {
  description = "The ARN of the EFS file system."
  value       = aws_efs_file_system.this.arn
}

output "efs_dns_name" {
  description = "The DNS name of the EFS file system."
  value       = aws_efs_file_system.this.dns_name
}