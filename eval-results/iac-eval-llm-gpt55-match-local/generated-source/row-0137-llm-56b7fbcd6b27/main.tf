terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the ElastiCache user group will be created."
  type        = string
  default     = "us-east-1"
}

variable "elasticache_user_group_id" {
  description = "ID of the ElastiCache Redis user group."
  type        = string
  default     = "example-redis-user-group"
}

variable "app_user_id" {
  description = "ID of the application ElastiCache Redis user."
  type        = string
  default     = "app-user"
}

variable "app_user_name" {
  description = "User name of the application ElastiCache Redis user."
  type        = string
  default     = "app-user"
}

resource "random_password" "app_user_password" {
  length           = 32
  special          = true
  override_special = "!&#$^<>-"
}

resource "aws_elasticache_user" "default" {
  user_id       = "default"
  user_name     = "default"
  engine        = "REDIS"
  access_string = "off ~* +@all"

  authentication_mode {
    type = "no-password-required"
  }
}

resource "aws_elasticache_user" "app" {
  user_id       = var.app_user_id
  user_name     = var.app_user_name
  engine        = "REDIS"
  access_string = "on ~* +@all"

  authentication_mode {
    type      = "password"
    passwords = [random_password.app_user_password.result]
  }
}

resource "aws_elasticache_user_group" "redis_user_group" {
  user_group_id = var.elasticache_user_group_id
  engine        = "REDIS"

  user_ids = [
    aws_elasticache_user.default.user_id,
    aws_elasticache_user.app.user_id
  ]
}

output "elasticache_user_group_id" {
  description = "The ID of the created ElastiCache user group."
  value       = aws_elasticache_user_group.redis_user_group.user_group_id
}

output "app_user_id" {
  description = "The ID of the application Redis user."
  value       = aws_elasticache_user.app.user_id
}

output "app_user_password" {
  description = "Generated password for the application Redis user."
  value       = random_password.app_user_password.result
  sensitive   = true
}