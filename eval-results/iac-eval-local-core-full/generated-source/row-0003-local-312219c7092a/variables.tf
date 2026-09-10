variable "db_username" {
  description = "Master username for the primary RDS instance."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the primary RDS instance. Override for real deployments."
  type        = string
  sensitive   = true
  default     = "ChangeMe123!"
}
