variable "name" {
  description = "Name prefix for the Aurora MySQL resources."
  type        = string
  default     = "aurora-mysql-demo"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_master_username" {
  description = "Master username for the Aurora MySQL cluster. The password is managed by AWS Secrets Manager."
  type        = string
  default     = "adminuser"
}
