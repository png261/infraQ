variable "allocated_storage" {
  description = "Allocated storage for the MySQL DB instance in GiB."
  type        = number
  default     = 20
}

variable "instance_class" {
  description = "Instance class for the MySQL DB instance."
  type        = string
  default     = "db.t3.micro"
}

variable "db_username" {
  description = "Master username for the MySQL DB instance."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the MySQL DB instance. Supply with TF_VAR_db_password or a tfvars file."
  type        = string
  sensitive   = true
}
