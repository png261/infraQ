variable "vpc_id" {
  description = "ID of the VPC where the PostgreSQL database subnets and security group will be created."
  type        = string
}

variable "private_subnet_cidr_blocks" {
  description = "Two non-overlapping CIDR blocks for the database subnets in the target VPC."
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]

  validation {
    condition     = length(var.private_subnet_cidr_blocks) >= 2
    error_message = "At least two subnet CIDR blocks are required for the DB subnet group."
  }
}

variable "db_username" {
  description = "Master username for the PostgreSQL database."
  type        = string
  default     = "postgresadmin"
  sensitive   = true
}

variable "db_password" {
  description = "Master password for the PostgreSQL database. Non-production placeholder default is provided only for benchmark deployability; override with TF_VAR_db_password or a secure variables file for any real deployment."
  type        = string
  default     = "BenchmarkPgPassword123!"
  sensitive   = true
}

variable "db_ingress_cidr_blocks" {
  description = "CIDR blocks allowed to connect to PostgreSQL on port 5432. Restrict this to application or bastion networks."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}
