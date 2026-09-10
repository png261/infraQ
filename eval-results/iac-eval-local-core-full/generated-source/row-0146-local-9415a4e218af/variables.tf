variable "cluster_identifier" {
  description = "Identifier for the Redshift cluster."
  type        = string
  default     = "example-redshift-cluster"
}

variable "database_name" {
  description = "Initial database name for the Redshift cluster."
  type        = string
  default     = "exampledb"
}

variable "master_username" {
  description = "Master username for the Redshift cluster."
  type        = string
  default     = "adminuser"
}

variable "master_password" {
  description = "Master password for the Redshift cluster. Must satisfy AWS Redshift password requirements."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.master_password) >= 8
    error_message = "The Redshift master password must be at least 8 characters long."
  }
}

variable "node_type" {
  description = "Node type for the Redshift cluster."
  type        = string
  default     = "dc2.large"
}

variable "iam_role_name" {
  description = "Name of the IAM role assumed by Redshift."
  type        = string
  default     = "example-redshift-role"
}
