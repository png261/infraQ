variable "db_username" {
  description = "Master username for the benchmark MySQL DB instance."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the benchmark MySQL DB instance."
  type        = string
  sensitive   = true
  default     = "BenchmarkPassw0rd!"
}
