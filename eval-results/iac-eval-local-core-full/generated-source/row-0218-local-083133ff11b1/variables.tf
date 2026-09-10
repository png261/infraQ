variable "master_username" {
  description = "Master username for the benchmark MySQL RDS cluster."
  type        = string
  sensitive   = true
  default     = "adminuser"
}

variable "master_password" {
  description = "Master password for the benchmark MySQL RDS cluster. Override for real deployments."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.master_password) >= 8
    error_message = "The master password must be at least 8 characters long."
  }
}

variable "db_cluster_instance_class" {
  description = "Instance class for the MySQL Multi-AZ DB cluster."
  type        = string
  default     = "db.m6gd.large"
}
