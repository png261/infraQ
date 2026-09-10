resource "aws_lightsail_database" "managed" {
  relational_database_name = "benchmark-managed-db"
  master_database_name     = "appdb"
  master_username          = "dbadmin"
  master_password          = var.master_password
  blueprint_id             = "mysql_8_0"
  bundle_id                = "micro_2_0"
}
