variable "db_username" {
  description = "Master username for the source RDS DB instance."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the source RDS DB instance. This value is sensitive and will still be stored in Terraform/OpenTofu state."
  type        = string
  sensitive   = true
}
