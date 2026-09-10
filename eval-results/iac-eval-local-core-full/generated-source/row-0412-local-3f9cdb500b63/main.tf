provider "aws" {
  region = "us-east-1"
}

resource "aws_db_instance" "resource1" {
  allocated_storage       = 20
  engine                  = "mysql"
  instance_class          = "db.t3.micro"
  username                = var.db_username
  password                = var.db_password
  backup_retention_period = 1
  skip_final_snapshot     = true
}

resource "aws_db_instance" "resource2" {
  instance_class      = "db.t3.micro"
  replicate_source_db = aws_db_instance.resource1.identifier
  skip_final_snapshot = true
}
