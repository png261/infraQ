variable "vpc_id" {
  description = "ID of the VPC where the PostgreSQL subnets and security group will be created."
  type        = string
}

variable "db_subnet_cidr_blocks" {
  description = "Two CIDR blocks for database subnets in the specified VPC."
  type        = list(string)

  validation {
    condition     = length(var.db_subnet_cidr_blocks) >= 2
    error_message = "At least two database subnet CIDR blocks are required."
  }
}

variable "db_subnet_availability_zones" {
  description = "Two availability zones in us-east-1 for the database subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.db_subnet_availability_zones) >= 2
    error_message = "At least two database subnet availability zones are required."
  }
}

variable "allowed_postgres_cidr_blocks" {
  description = "CIDR blocks allowed to connect to PostgreSQL on port 5432."
  type        = list(string)
  default     = []
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "benchmarkdb"
}

variable "db_username" {
  description = "Master username for the PostgreSQL database."
  type        = string
  default     = "benchmark_admin"
}

variable "db_password" {
  description = "Master password for the PostgreSQL database. Provide securely via tfvars, environment variable, or a secrets manager workflow."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "The database password must be at least 8 characters long."
  }
}
