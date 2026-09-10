variable "db_username" {
  description = "Master username for the MySQL RDS instance."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the MySQL RDS instance. Provide with TF_VAR_db_password or a tfvars file."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "The database password must be at least 8 characters long."
  }
}
