resource "aws_kms_key" "db_master_secret" {
  description             = "KMS key for the RDS managed master user secret"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_db_instance" "database" {
  allocated_storage               = 20
  engine                          = "postgres"
  instance_class                  = "db.t3.micro"
  username                        = "dbadmin"
  manage_master_user_password     = true
  master_user_secret_kms_key_id   = aws_kms_key.db_master_secret.arn
  skip_final_snapshot             = true
  publicly_accessible             = false
}
