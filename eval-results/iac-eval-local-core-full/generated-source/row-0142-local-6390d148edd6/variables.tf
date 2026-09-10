variable "redshift_master_password" {
  description = "Master password for the benchmark Redshift cluster. Provide via TF_VAR_redshift_master_password or a secure variable source."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.redshift_master_password) >= 8 && length(var.redshift_master_password) <= 64
    error_message = "The Redshift master password must be between 8 and 64 characters."
  }
}
