variable "cluster_identifier" {
  description = "Identifier for the Redshift cluster."
  type        = string
  default     = "iac-eval-redshift-cluster"
}

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
  description = "Master password for the Redshift cluster. Supply with TF_VAR_master_password or a tfvars file; do not commit real secrets."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.master_password) >= 8
    error_message = "The master_password value must be at least 8 characters long."
  }
}

variable "node_type" {
  description = "Node type for the Redshift cluster."
  type        = string
  default     = "dc2.large"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC hosting the private Redshift cluster."
  type        = string
  default     = "10.0.0.0/16"
}

variable "redshift_subnet_cidr_blocks" {
  description = "Map of us-east-1 availability zones to subnet CIDR blocks for the Redshift subnet group."
  type        = map(string)
  default = {
    "us-east-1a" = "10.0.1.0/24"
    "us-east-1b" = "10.0.2.0/24"
  }
}
