variable "db_password" {
  description = "Master password for the RDS instance. Provide at plan/apply time; this value is sensitive and will be stored in Terraform state."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8 && length(var.db_password) <= 41
    error_message = "The RDS master password must be between 8 and 41 characters."
  }
}
