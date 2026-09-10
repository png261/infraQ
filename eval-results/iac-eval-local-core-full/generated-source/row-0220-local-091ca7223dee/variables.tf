variable "db_username" {
  description = "Master username for the PostgreSQL DB instance."
  type        = string
  default     = "postgresadmin"
}

variable "db_password" {
  description = "Master password for the PostgreSQL DB instance. Provide via TF_VAR_db_password or a tfvars file; it will still be stored in Terraform/OpenTofu state by the AWS provider."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "db_password must be at least 8 characters long."
  }
}
