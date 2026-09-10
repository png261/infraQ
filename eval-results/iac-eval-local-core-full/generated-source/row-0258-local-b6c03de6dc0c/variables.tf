variable "redshift_master_password" {
  description = "Master password for the example Redshift cluster. Override for real deployments."
  type        = string
  sensitive   = true
  default     = "BenchmarkPassw0rd123"

  validation {
    condition     = length(var.redshift_master_password) >= 8 && length(var.redshift_master_password) <= 64
    error_message = "The Redshift master password must be between 8 and 64 characters."
  }
}
