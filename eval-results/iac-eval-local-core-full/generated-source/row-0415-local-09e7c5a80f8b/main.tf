resource "aws_db_instance" "basic" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t3.micro"
  password             = var.db_password
  username             = "dbadmin"
  storage_type         = "io1"
  iops                 = 1000
  skip_final_snapshot  = true
}
