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
  description = "ID for the ElastiCache user group."
  type        = string
  default     = "example-redis-user-group"
}

resource "random_password" "app_user_password" {
  length           = 32
  special          = true
  override_special = "!&#$^<>-"
}

resource "random_password" "readonly_user_password" {
  length           = 32
  special          = true
  override_special = "!&#$^<>-"
}

resource "aws_elasticache_user" "default" {
  user_id       = "default"
  user_name     = "default"
  engine        = "REDIS"
  access_string = "on ~* +@all"

  no_password_required = true

  tags = {
    Name        = "default-redis-user"
    Environment = "example"
  }
}

resource "aws_elasticache_user" "app_user" {
  user_id       = "app-user"
  user_name     = "app-user"
  engine        = "REDIS"
  access_string = "on ~* +@all"

  passwords = [
    random_password.app_user_password.result
  ]

  tags = {
    Name        = "app-redis-user"
    Environment = "example"
  }
}

resource "aws_elasticache_user" "readonly_user" {
  user_id       = "readonly-user"
  user_name     = "readonly-user"
  engine        = "REDIS"
  access_string = "on ~* +@read"

  passwords = [
    random_password.readonly_user_password.result
  ]

  tags = {
    Name        = "readonly-redis-user"
    Environment = "example"
  }
}

resource "aws_elasticache_user_group" "redis_user_group" {
  user_group_id = var.elasticache_user_group_id
  engine        = "REDIS"

  user_ids = [
    aws_elasticache_user.default.user_id,
    aws_elasticache_user.app_user.user_id,
    aws_elasticache_user.readonly_user.user_id
  ]

  tags = {
    Name        = var.elasticache_user_group_id
    Environment = "example"
  }
}

output "elasticache_user_group_id" {
  description = "The ID of the created ElastiCache user group."
  value       = aws_elasticache_user_group.redis_user_group.user_group_id
}

output "elasticache_user_ids" {
  description = "The IDs of the users in the ElastiCache user group."
  value = [
    aws_elasticache_user.default.user_id,
    aws_elasticache_user.app_user.user_id,
    aws_elasticache_user.readonly_user.user_id
  ]
}

output "app_user_password" {
  description = "Generated password for the application Redis user."
  value       = random_password.app_user_password.result
  sensitive   = true
}

output "readonly_user_password" {
  description = "Generated password for the read-only Redis user."
  value       = random_password.readonly_user_password.result
  sensitive   = true
}