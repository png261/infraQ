variable "redshift_master_password" {
  description = "Master password for the Redshift cluster. Provide via TF_VAR_redshift_master_password or a local tfvars file; do not commit real secrets."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.redshift_master_password) >= 8
    error_message = "The Redshift master password must be at least 8 characters long."
  }
}
