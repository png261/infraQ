locals {
  elasticache_users = {
    application = {
      user_id       = "application-user"
      user_name     = "application"
      access_string = "on ~app:* +@read +@write"
    }
    readonly = {
      user_id       = "readonly-user"
      user_name     = "readonly"
      access_string = "on ~app:* +@read"
    }
  }
}

resource "aws_elasticache_user" "default" {
  user_id       = "default"
  user_name     = "default"
  access_string = "on ~* +@all"
  engine        = "REDIS"

  authentication_mode {
    type = "no-password-required"
  }
}

resource "aws_elasticache_user" "this" {
  for_each = local.elasticache_users

  user_id       = each.value.user_id
  user_name     = each.value.user_name
  access_string = each.value.access_string
  engine        = "REDIS"

  authentication_mode {
    type = "no-password-required"
  }
}

resource "aws_elasticache_user_group" "this" {
  engine        = "REDIS"
  user_group_id = "example-redis-user-group"
  user_ids      = concat([aws_elasticache_user.default.user_id], [for user in aws_elasticache_user.this : user.user_id])
}
