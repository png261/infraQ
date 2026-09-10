variable "redshift_admin_username" {
  description = "Admin username for the Redshift cluster."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,126}$", var.redshift_admin_username))
    error_message = "Redshift admin username must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "redshift_admin_password" {
  description = "Admin password for the Redshift cluster. Provide via TF_VAR_redshift_admin_password or a secure variable source."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.redshift_admin_password) >= 8
    error_message = "Redshift admin password must be at least 8 characters long."
  }
}
