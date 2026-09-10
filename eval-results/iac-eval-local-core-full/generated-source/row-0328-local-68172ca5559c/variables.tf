variable "db_instance_class" {
  description = "Instance class for the PostgreSQL RDS instance."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "Initial database name for DolphinScheduler."
  type        = string
  default     = "dolphinscheduler"
}

variable "db_username" {
  description = "Master username for the PostgreSQL RDS instance."
  type        = string
  default     = "dolphinscheduler"
}

variable "db_password" {
  description = "Master password for the PostgreSQL RDS instance. Supply via tfvars or TF_VAR_db_password."
  type        = string
  sensitive   = true
}
