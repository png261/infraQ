variable "db_username" {
  description = "Master username for the MySQL DB instance."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the MySQL DB instance. This value is sensitive and will be stored in Terraform/OpenTofu state."
  type        = string
  sensitive   = true
}
