variable "db_username" {
  description = "Master username for the Airbyte connector test PostgreSQL database."
  type        = string
  default     = "airbyte"
}

variable "db_password" {
  description = "Master password for the Airbyte connector test PostgreSQL database. Provide via TF_VAR_db_password or a secure variable store."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8 && length(var.db_password) <= 128
    error_message = "db_password must be between 8 and 128 characters to satisfy RDS master password length requirements."
  }

  validation {
    condition     = !strcontains(var.db_password, "/") && !strcontains(var.db_password, "\"") && !strcontains(var.db_password, "@")
    error_message = "db_password must not contain '/', double quote, or '@' characters, which are not allowed in RDS master passwords."
  }
}
