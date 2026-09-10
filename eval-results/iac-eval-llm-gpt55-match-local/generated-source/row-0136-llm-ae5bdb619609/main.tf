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
  region = "us-east-1"
}

provider "random" {}

resource "random_password" "elasticache_user_password" {
  length  = 32
  special = false
}

resource "aws_elasticache_user" "redis_user" {
  user_id       = "redis-app-user"
  user_name     = "redis-app-user"
  engine        = "REDIS"
  access_string = "on ~* +@all"

  authentication_mode {
    type      = "password"
    passwords = [random_password.elasticache_user_password.result]
  }
}

output "elasticache_user_id" {
  value = aws_elasticache_user.redis_user.user_id
}

output "elasticache_user_name" {
  value = aws_elasticache_user.redis_user.user_name
}

output "elasticache_user_password" {
  value     = random_password.elasticache_user_password.result
  sensitive = true
}