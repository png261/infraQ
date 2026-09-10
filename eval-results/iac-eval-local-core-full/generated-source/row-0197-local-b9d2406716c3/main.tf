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
  region = "us-east-1"
}

locals {
  elasticache_users = {
    default = {
      user_id       = "default"
      user_name     = "default"
      access_string = "on ~* +@all"
    }
    app_reader = {
      user_id       = "app-reader"
      user_name     = "app-reader"
      access_string = "on ~* +@read"
    }
    app_writer = {
      user_id       = "app-writer"
      user_name     = "app-writer"
      access_string = "on ~* +@write +@read"
    }
  }
}

resource "aws_elasticache_user" "this" {
  for_each = local.elasticache_users

  user_id              = each.value.user_id
  user_name            = each.value.user_name
  access_string        = each.value.access_string
  engine               = "REDIS"
  no_password_required = true
}

resource "aws_elasticache_user_group" "this" {
  user_group_id = "benchmark-redis-user-group"
  engine        = "REDIS"
  user_ids      = [for user in aws_elasticache_user.this : user.user_id]
}
