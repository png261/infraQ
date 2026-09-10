resource "aws_lightsail_database" "postgres" {
  relational_database_name = "benchmark-postgres-db"
  master_database_name     = "appdb"
  master_username          = "dbadmin"
  master_password          = var.master_password
  blueprint_id             = "postgres_12"
  bundle_id                = "micro_2_0"
  apply_immediately        = true
}
