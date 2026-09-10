variable "db_username" {
  description = "Master username for the PostgreSQL DB instance."
  type        = string
  default     = "postgresadmin"
}

variable "db_password" {
  description = "Master password for the PostgreSQL DB instance. Override for real deployments."
  type        = string
  sensitive   = true
  default     = "ChangeMe123!"
}
