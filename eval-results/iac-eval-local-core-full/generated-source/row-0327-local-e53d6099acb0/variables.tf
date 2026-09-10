variable "db_username" {
  description = "Master username for the PostgreSQL benchmark database."
  type        = string
  default     = "benchmark_admin"
}

variable "db_password" {
  description = "Master password for the PostgreSQL benchmark database. Supplied by the operator to avoid committing secrets."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "The database password must be at least 8 characters long."
  }
}
