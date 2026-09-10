provider "aws" {
  region = "us-east-1"
}

resource "aws_elasticache_user" "iam_user" {
  user_id       = "iam-elasticache-user"
  user_name     = "iam-elasticache-user"
  engine        = "REDIS"
  access_string = "on ~* +@all"

  authentication_mode {
    type = "iam"
  }
}
