variable "redshift_master_password" {
  description = "Master password for the example Redshift cluster. This value is sensitive and will be stored in Terraform/OpenTofu state by the AWS provider."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.redshift_master_password) >= 8
    error_message = "The Redshift master password must be at least 8 characters long."
  }
}
