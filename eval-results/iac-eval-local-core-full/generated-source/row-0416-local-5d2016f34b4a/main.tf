resource "aws_db_instance" "restored_from_s3" {
  allocated_storage = 20
  engine            = "mysql"
  instance_class    = "db.t3.micro"
  username          = var.db_username
  password          = var.db_password

  s3_import {
    bucket_name           = var.s3_import_bucket_name
    ingestion_role        = var.s3_import_role_arn
    source_engine         = "mysql"
    source_engine_version = "8.0"
  }

  db_name              = "appdb"
  skip_final_snapshot  = true
  publicly_accessible  = false
  deletion_protection  = false
}
