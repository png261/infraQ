terraform {
  required_version = ">= 1.3.0"

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
  description = "AWS region where the existing ElastiCache user and user group are located."
  type        = string
  default     = "us-east-1"
}

variable "elasticache_user_id" {
  description = "The ID of the existing ElastiCache user to associate with the user group."
  type        = string
  default     = "existing-elasticache-user"
}

variable "elasticache_user_group_id" {
  description = "The ID of the existing ElastiCache user group."
  type        = string
  default     = "existing-elasticache-user-group"
}

resource "aws_elasticache_user_group_association" "existing_user_association" {
  user_group_id = var.elasticache_user_group_id
  user_id       = var.elasticache_user_id
}

output "elasticache_user_group_id" {
  description = "The ElastiCache user group ID."
  value       = aws_elasticache_user_group_association.existing_user_association.user_group_id
}

output "elasticache_user_id" {
  description = "The associated ElastiCache user ID."
  value       = aws_elasticache_user_group_association.existing_user_association.user_id
}