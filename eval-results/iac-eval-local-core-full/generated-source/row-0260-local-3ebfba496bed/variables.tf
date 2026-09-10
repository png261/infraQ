variable "redshift_master_username" {
  description = "Master username for the example Redshift cluster."
  type        = string
  default     = "adminuser"
}

variable "redshift_master_password" {
  description = "Master password for the example Redshift cluster. Provide via TF_VAR_redshift_master_password."
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(var.redshift_master_password) >= 8
    error_message = "The Redshift master password must be at least 8 characters long."
  }
}
