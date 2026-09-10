variable "db_username" {
  description = "Master username for the MySQL instance."
  type        = string
  default     = "adminuser"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,15}$", var.db_username))
    error_message = "db_username must start with a letter, contain only letters, numbers, and underscores, and be 1-16 characters long."
  }
}

variable "db_password" {
  description = "Master password for the MySQL instance. Provide via TF_VAR_db_password or a tfvars file that is not committed."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "db_password must be at least 8 characters long."
  }
}
