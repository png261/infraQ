variable "allocated_storage" {
  description = "Allocated storage for the PostgreSQL DB instance in GiB."
  type        = number
  default     = 20
}

variable "engine_version" {
  description = "PostgreSQL engine version for the DB instance."
  type        = string
  default     = "16.3"
}

variable "instance_class" {
  description = "Instance class for the PostgreSQL DB instance."
  type        = string
  default     = "db.t3.micro"
}

variable "database_name" {
  description = "Initial database name."
  type        = string
  default     = "benchmarkdb"
}

variable "database_username" {
  description = "Master username for the PostgreSQL DB instance."
  type        = string
  default     = "benchmark_admin"
}

variable "database_password" {
  description = "Master password for the PostgreSQL DB instance. Provide with TF_VAR_database_password or a tfvars file not committed to source control."
  type        = string
  sensitive   = true
}
