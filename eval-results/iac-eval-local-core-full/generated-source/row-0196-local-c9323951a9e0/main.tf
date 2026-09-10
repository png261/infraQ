resource "aws_elasticache_user" "password_authenticated" {
  user_id       = "benchmark-redis-user"
  user_name     = "benchmark-redis-user"
  engine        = "REDIS"
  access_string = "on ~* +@all"

  authentication_mode {
    type      = "password"
    passwords = ["password1", "password2"]
  }
}
