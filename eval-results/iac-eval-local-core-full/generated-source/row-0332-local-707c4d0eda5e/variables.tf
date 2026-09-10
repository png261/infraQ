variable "vpc_id" {
  description = "ID of the existing VPC where the PostgreSQL subnets, security group, and RDS instance will be provisioned."
  type        = string
}

variable "database_subnet_cidr_blocks" {
  description = "Two non-overlapping CIDR blocks within the specified VPC for the database subnets."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]

  validation {
    condition     = length(var.database_subnet_cidr_blocks) >= 2
    error_message = "At least two database subnet CIDR blocks are required."
  }
}

variable "allowed_postgres_cidr_blocks" {
  description = "CIDR blocks allowed to connect to PostgreSQL on port 5432. Keep this restricted to application or administration networks."
  type        = list(string)
  default     = []
}

variable "allocated_storage" {
  description = "Allocated storage for the PostgreSQL RDS instance in GiB."
  type        = number
  default     = 20
}

variable "postgres_engine_version" {
  description = "PostgreSQL engine version compatible with the postgres15 parameter group family."
  type        = string
  default     = "15.5"
}

variable "database_name" {
  description = "Initial database name to create."
  type        = string
  default     = "appdb"
}

variable "database_username" {
  description = "Master username for the PostgreSQL RDS instance."
  type        = string
  default     = "dbadmin"
}

variable "database_password" {
  description = "Master password for the PostgreSQL RDS instance. Supply via tfvars or environment variable; do not commit secrets."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.database_password) >= 8
    error_message = "The database password must be at least 8 characters long."
  }
}

variable "enable_multi_az" {
  description = "Whether to request a Multi-AZ RDS deployment. Defaults to true to satisfy the benchmark high-availability requirement; if AWS rejects db.t3.micro with Multi-AZ in the target account/region, set this to false or choose a supported instance class outside the benchmark constraints."
  type        = bool
  default     = true
}
