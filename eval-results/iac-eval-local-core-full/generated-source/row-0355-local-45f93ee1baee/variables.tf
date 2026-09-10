variable "project_name" {
  description = "Name prefix used for created resources."
  type        = string
  default     = "aurora-proxy-demo"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr_blocks" {
  description = "CIDR blocks for the two private database subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.subnet_cidr_blocks) == 2
    error_message = "Exactly two subnet CIDR blocks are required."
  }
}

variable "db_name" {
  description = "Initial database name for the Aurora MySQL cluster."
  type        = string
  default     = "appdb"
}

variable "db_master_username" {
  description = "Master username for the Aurora MySQL cluster."
  type        = string
  default     = "adminuser"
}

variable "db_master_password" {
  description = "Master password for the Aurora MySQL cluster. Supply with TF_VAR_db_master_password or a tfvars file."
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "Instance class for the Aurora MySQL cluster instance."
  type        = string
  default     = "db.t3.medium"
}
