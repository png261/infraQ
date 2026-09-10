variable "db_username" {
  description = "Master username for the benchmark RDS instance."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the benchmark RDS instance."
  type        = string
  sensitive   = true
}
