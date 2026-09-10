variable "domain_name" {
  description = "Domain name to manage with Route 53."
  type        = string
  default     = "example.com"
}

variable "db_username" {
  description = "Master username for the RDS database."
  type        = string
  default     = "myappuser"
}

variable "db_password" {
  description = "Master password for the RDS database. Provide a strong value for real deployments."
  type        = string
  sensitive   = true
  default     = "ChangeMe123!"
}
