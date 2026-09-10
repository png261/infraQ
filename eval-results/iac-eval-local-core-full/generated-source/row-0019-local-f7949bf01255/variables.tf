variable "db_password" {
  description = "Password for the shared RDS database. Provide via TF_VAR_db_password or a tfvars file."
  type        = string
  sensitive   = true
  default     = "ChangeMe123!"
}
