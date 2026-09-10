variable "db_username" {
  description = "Master username for the PostgreSQL DB instance."
  type        = string
  default     = "postgresadmin"
}

variable "db_password" {
  description = "Master password for the PostgreSQL DB instance. Provide a benchmark-only value via tfvars or CLI input. This value is sensitive but will still be stored in Terraform/OpenTofu state."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "The database password must be at least 8 characters long."
  }
}
