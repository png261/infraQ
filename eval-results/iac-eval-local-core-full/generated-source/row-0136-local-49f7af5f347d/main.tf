provider "aws" {
  region = "us-east-1"
}

resource "aws_elasticache_user" "benchmark" {
  user_id       = "benchmark-user"
  user_name     = "benchmark-user"
  access_string = "on ~* +@all"
  engine        = "REDIS"

  authentication_mode {
    type      = "password"
    passwords = ["password1", "password2"]
  }
}
