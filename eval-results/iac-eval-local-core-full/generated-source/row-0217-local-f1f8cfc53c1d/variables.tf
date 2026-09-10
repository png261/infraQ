variable "db_master_username" {
  description = "Master username for the benchmark MySQL RDS cluster."
  type        = string
  default     = "adminuser"
}

variable "db_master_password" {
  description = "Master password for the benchmark MySQL RDS cluster. Override for real deployments."
  type        = string
  sensitive   = true
  default     = "ChangeMe123456789!"

  validation {
    condition     = length(var.db_master_password) >= 8
    error_message = "The DB master password must be at least 8 characters long."
  }
}
