variable "cluster_identifier" {
  description = "Identifier for the Redshift cluster."
  type        = string
  default     = "iac-eval-redshift"
}

variable "database_name" {
  description = "Name of the initial Redshift database."
  type        = string
  default     = "dev"
}

variable "master_username" {
  description = "Master username for the Redshift cluster."
  type        = string
  default     = "adminuser"
}

variable "master_password" {
  description = "Master password for the Redshift cluster. Supply via TF_VAR_master_password or a tfvars file that is not committed."
  type        = string
  sensitive   = true
}

variable "node_type" {
  description = "Redshift node type for the two-node cluster."
  type        = string
  default     = "dc2.large"
}

variable "snapshot_copy_retention_days" {
  description = "Number of days to retain automated snapshot copies in us-east-2."
  type        = number
  default     = 7
}
