variable "db_username" {
  description = "Master username for the benchmark RDS instance."
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "EVAL ONLY default master password for the benchmark RDS instance. Override via terraform.tfvars or TF_VAR_db_password for any real deployment; the benchmark also passes this value into Elastic Beanstalk environment settings, which is not appropriate for production secrets."
  type        = string
  sensitive   = true
  default     = "EvalOnlyDbPassword123!"

  validation {
    condition     = length(var.db_password) >= 8 && length(var.db_password) <= 128
    error_message = "db_password must be between 8 and 128 characters to satisfy RDS password constraints."
  }
}
