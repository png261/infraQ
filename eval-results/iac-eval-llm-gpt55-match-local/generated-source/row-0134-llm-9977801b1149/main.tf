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
  description = "AWS region where the ElastiCache Redis user will be created."
  type        = string
  default     = "us-east-1"
}

variable "elasticache_user_id" {
  description = "Unique ID for the ElastiCache Redis user."
  type        = string
  default     = "redis-app-user"
}

variable "elasticache_user_name" {
  description = "User name for the ElastiCache Redis user."
  type        = string
  default     = "redis-app-user"
}

variable "redis_password" {
  description = "Password for the ElastiCache Redis user. Must be at least 16 characters."
  type        = string
  sensitive   = true
  default     = "RedisSecurePassword123!"
}

resource "aws_elasticache_user" "redis_user" {
  user_id       = var.elasticache_user_id
  user_name     = var.elasticache_user_name
  engine        = "REDIS"
  access_string = "on ~* +@all"

  authentication_mode {
    type      = "password"
    passwords = [var.redis_password]
  }
}

output "elasticache_user_id" {
  description = "The ID of the ElastiCache Redis user."
  value       = aws_elasticache_user.redis_user.user_id
}

output "elasticache_user_name" {
  description = "The name of the ElastiCache Redis user."
  value       = aws_elasticache_user.redis_user.user_name
}