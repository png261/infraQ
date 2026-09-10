provider "aws" {
  region = "us-east-1"
}

resource "aws_db_instance" "mysql" {
  allocated_storage   = var.allocated_storage
  engine              = "mysql"
  instance_class      = var.instance_class
  username            = var.db_username
  password            = var.db_password
  apply_immediately   = true
  skip_final_snapshot = true
}
