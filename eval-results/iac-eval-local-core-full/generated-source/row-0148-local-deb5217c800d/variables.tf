variable "database_name" {
  description = "Initial database name for the Redshift cluster."
  type        = string
  default     = "dev"
}

variable "master_username" {
  description = "Master username for the Redshift cluster."
  type        = string
  default     = "adminuser"
}

variable "master_password" {
  description = "Master password for the Redshift cluster. Must meet AWS Redshift password requirements."
  type        = string
  sensitive   = true
}

variable "node_type" {
  description = "Redshift node type for the two-node benchmark cluster."
  type        = string
  default     = "ra3.xlplus"
}
