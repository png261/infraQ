provider "aws" {
  region = "us-east-1"
}

resource "aws_elasticache_user" "redis_user" {
  user_id       = "benchmark-redis-user"
  user_name     = "benchmark-redis-user"
  engine        = "REDIS"
  access_string = "on ~* +@read"

  no_password_required = true
}
