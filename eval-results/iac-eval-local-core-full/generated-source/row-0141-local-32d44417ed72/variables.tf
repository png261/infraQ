variable "redshift_master_username" {
  description = "Master username for the benchmark Redshift cluster."
  type        = string
  default     = "adminuser"
}

variable "redshift_master_password" {
  description = "Master password for the benchmark Redshift cluster. Override for real deployments."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}
