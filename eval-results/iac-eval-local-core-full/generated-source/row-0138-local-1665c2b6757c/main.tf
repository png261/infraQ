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

resource "aws_elasticache_user" "default" {
  user_id       = "benchmark-default-user"
  user_name     = "default"
  access_string = "on ~* +@all"
  engine        = "REDIS"

  no_password_required = true
}

resource "aws_elasticache_user" "application" {
  user_id       = "benchmark-application-user"
  user_name     = "benchmark-application-user"
  access_string = "on ~* +@read +@write"
  engine        = "REDIS"

  no_password_required = true
}

resource "aws_elasticache_user_group" "benchmark" {
  user_group_id = "benchmark-user-group"
  engine        = "REDIS"

  user_ids = [aws_elasticache_user.default.user_id]
}

resource "aws_elasticache_user_group_association" "application" {
  user_group_id = aws_elasticache_user_group.benchmark.user_group_id
  user_id       = aws_elasticache_user.application.user_id
}
