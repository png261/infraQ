variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_name" {
  description = "Initial database name for the Aurora MySQL cluster."
  type        = string
  default     = "appdb"
}

variable "db_master_username" {
  description = "Master username for the Aurora MySQL cluster."
  type        = string
  sensitive   = true
  default     = "adminuser"
}

variable "db_master_password" {
  description = "Master password for the Aurora MySQL cluster. Provide a strong value for real deployments."
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "Instance class for the Aurora MySQL cluster instance."
  type        = string
  default     = "db.t3.medium"
}
