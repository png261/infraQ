variable "vpc_cidr_block" {
  description = "CIDR block for the Airbyte connector test VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "public_subnet_cidr_block" {
  description = "CIDR block for the public subnet included in the RDS subnet group."
  type        = string
  default     = "10.40.1.0/24"
}

variable "private_subnet_cidr_block" {
  description = "CIDR block for the private subnet included in the RDS subnet group."
  type        = string
  default     = "10.40.2.0/24"
}

variable "db_instance_class" {
  description = "Instance class for the PostgreSQL 15 RDS instance."
  type        = string
  default     = "db.t3.medium"
}

variable "db_username" {
  description = "Master username for the PostgreSQL 15 RDS instance."
  type        = string
  default     = "airbyte"
}

variable "db_password" {
  description = "Master password for the PostgreSQL 15 RDS instance. Supply via TF_VAR_db_password or a tfvars file."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "db_password must be at least 8 characters long."
  }
}
