variable "db_username" {
  description = "Master username for the benchmark PostgreSQL RDS instance."
  type        = string
  default     = "benchmarkadmin"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.db_username))
    error_message = "db_username must begin with a letter and contain only letters, numbers, or underscores, up to 63 characters."
  }
}

variable "db_password" {
  description = "Master password for the benchmark PostgreSQL RDS instance. This value is sensitive and will still be stored in Terraform/OpenTofu state."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8 && length(var.db_password) <= 128
    error_message = "db_password must be between 8 and 128 characters."
  }
}

variable "database_access_cidr" {
  description = "CIDR block allowed to connect to PostgreSQL on port 5432. Defaults to public access for benchmark purposes."
  type        = string
  default     = "0.0.0.0/0"
}
