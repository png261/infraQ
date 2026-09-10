resource "aws_elasticache_user" "redis_user" {
  user_id       = "benchmark-redis-user"
  user_name     = "benchmark-redis-user"
  access_string = "on ~* +@all"
  engine        = "REDIS"

  authentication_mode {
    type = "no-password-required"
  }
}
