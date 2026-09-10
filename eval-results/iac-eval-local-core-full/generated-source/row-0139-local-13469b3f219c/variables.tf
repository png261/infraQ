variable "redshift_master_password" {
  description = "Master password for the benchmark Redshift cluster. Provide via TF_VAR_redshift_master_password or a tfvars file; do not commit real secrets."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.redshift_master_password) >= 8 && can(regex("[A-Z]", var.redshift_master_password)) && can(regex("[a-z]", var.redshift_master_password)) && can(regex("[0-9]", var.redshift_master_password))
    error_message = "The Redshift master password must be at least 8 characters and include uppercase, lowercase, and numeric characters."
  }
}
