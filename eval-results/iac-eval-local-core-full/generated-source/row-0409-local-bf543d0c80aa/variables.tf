variable "db_username" {
  description = "Master username for the PostgreSQL DB instance."
  type        = string
  default     = "postgresadmin"
}

variable "db_password" {
  description = "Master password for the PostgreSQL DB instance. This value is stored in Terraform/OpenTofu state."
  type        = string
  sensitive   = true
}
