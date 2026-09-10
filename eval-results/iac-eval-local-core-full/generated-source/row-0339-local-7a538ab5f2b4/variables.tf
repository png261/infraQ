variable "db_instance_class" {
  description = "Instance class for the MySQL RDS instance."
  type        = string
  default     = "db.t3.micro"
}

variable "db_username" {
  description = "Master username for the MySQL RDS instance."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the MySQL RDS instance. This value is sensitive and will still be stored in Terraform/OpenTofu state."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "db_password must be at least 8 characters long."
  }
}

variable "db_allowed_cidr" {
  description = "CIDR block allowed to connect to MySQL on port 3306. Defaults to open access for the public-access benchmark requirement."
  type        = string
  default     = "0.0.0.0/0"
}
