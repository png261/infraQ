variable "db_username" {
  description = "Master username for the PostgreSQL database instance."
  type        = string
  default     = "benchmark_admin"
}

variable "db_password" {
  description = "Master password for the PostgreSQL database instance. Provide via tfvars or TF_VAR_db_password."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "The database password must be at least 8 characters long."
  }
}
