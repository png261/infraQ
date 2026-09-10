variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidr_blocks" {
  description = "CIDR blocks for private subnets used by the Aurora DB subnet group. Aurora requires subnets in at least two Availability Zones."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "Availability Zones for the private subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "cluster_identifier" {
  description = "Identifier for the Aurora PostgreSQL cluster."
  type        = string
  default     = "aurora-postgresql-example"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version."
  type        = string
  default     = "15.4"
}

variable "instance_class" {
  description = "Instance class for the Aurora PostgreSQL cluster instance."
  type        = string
  default     = "db.t3.medium"
}

variable "database_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Master username for the Aurora PostgreSQL cluster."
  type        = string
  default     = "dbadmin"
}

variable "master_password" {
  description = "Master password for the Aurora PostgreSQL cluster. Provide with TF_VAR_master_password or a tfvars file."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.master_password) >= 8
    error_message = "The master password must be at least 8 characters long."
  }
}
