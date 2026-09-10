resource "aws_elasticache_user" "iam" {
  user_id       = "benchmark-iam-user"
  user_name     = "benchmark-iam-user"
  access_string = "on ~* +@all"
  engine        = "REDIS"

  authentication_mode {
    type = "iam"
  }
}
