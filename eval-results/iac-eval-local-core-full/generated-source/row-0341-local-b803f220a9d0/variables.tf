variable "db_username" {
  description = "Master username for the PostgreSQL RDS instance."
  type        = string
  default     = "postgresadmin"
}

variable "db_password" {
  description = "Master password for the PostgreSQL RDS instance."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}
